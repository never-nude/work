import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Google OAuth for an "iOS" type client: authorization code + PKCE, no client secret,
/// no SDK. The refresh token is kept in the Keychain.
@MainActor
final class GoogleAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuth()
    private static let scope = "https://www.googleapis.com/auth/youtube"
    private static let refreshKey = "google.refreshToken"

    @Published private(set) var isSignedIn: Bool

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var webSession: ASWebAuthenticationSession?

    private override init() {
        isSignedIn = Keychain.get(Self.refreshKey) != nil
        super.init()
    }

    /// Accepts "123-abc.apps.googleusercontent.com" or the reversed form Google also shows.
    static func normalize(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let reversedPrefix = "com.googleusercontent.apps."
        if s.hasPrefix(reversedPrefix) {
            return String(s.dropFirst(reversedPrefix.count)) + ".apps.googleusercontent.com"
        }
        return s
    }

    /// True only for a real client ID: digits, a dash, letters/digits, then the Google suffix.
    static func isPlausible(_ raw: String) -> Bool {
        normalize(raw).range(of: #"^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil
    }

    private var clientID: String { Self.normalize(AppSettings.shared.clientID) }

    private var redirectScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    private var redirectURI: String { redirectScheme + ":/oauth2redirect" }

    func signIn() async throws {
        guard Self.isPlausible(clientID) else {
            throw AppError("That isn't a Google OAuth client ID. It looks like 1234567890-abc123.apps.googleusercontent.com")
        }
        let verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "consent")
        ]
        let authURL = components.url!
        let scheme = redirectScheme

        // Captured now, on the main thread, so the system can ask for it from any thread.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        anchor = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme,
                completionHandler: Self.handler(continuation, once)
            )
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            if !session.start(), once.claim() {
                continuation.resume(throwing: AppError("Couldn't open the Google sign-in sheet."))
            }
        }
        webSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let problem = items.first(where: { $0.name == "error" })?.value {
            throw AppError("Google sign-in failed: \(problem)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AppError("Google sign-in returned no authorization code.")
        }

        let json = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ])
        guard let refresh = json["refresh_token"] as? String else {
            throw AppError("Google didn't return a refresh token. Try signing in again.")
        }
        Keychain.set(refresh, for: Self.refreshKey)
        store(json)
        isSignedIn = true
    }

    /// A usable access token, refreshed when it is within a minute of expiring.
    func validToken() async throws -> String {
        if let accessToken, expiry.timeIntervalSinceNow > 60 { return accessToken }
        guard let refresh = Keychain.get(Self.refreshKey) else {
            isSignedIn = false
            throw AppError("Not signed in to Google.")
        }
        do {
            let json = try await tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": clientID
            ])
            store(json)
        } catch let error as TokenError where error.code == "invalid_grant" {
            signOut()
            throw AppError("Google sign-in expired. Sign in again.")
        }
        guard let accessToken else { throw AppError("Google returned no access token.") }
        return accessToken
    }

    func signOut() {
        Keychain.set(nil, for: Self.refreshKey)
        accessToken = nil
        expiry = .distantPast
        isSignedIn = false
        AppSettings.shared.channelTitle = ""
        AppSettings.shared.forgetStream()
    }

    private struct TokenError: Error { let code: String }

    private func store(_ json: [String: Any]) {
        accessToken = json["access_token"] as? String
        let lifetime = (json["expires_in"] as? Double) ?? 3000
        expiry = Date().addingTimeInterval(lifetime)
    }

    private func tokenRequest(_ params: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = json["error"] as? String ?? "unknown"
            if code == "invalid_grant" { throw TokenError(code: code) }
            let detail = json["error_description"] as? String ?? code
            throw AppError("Google token error: \(detail)")
        }
        return json
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }

    /// The system may call this back on a background queue, so it must not be tied to the main actor.
    private nonisolated static func handler(
        _ continuation: CheckedContinuation<URL, Error>,
        _ once: Once
    ) -> @Sendable (URL?, Error?) -> Void {
        { url, error in
            guard once.claim() else { return }
            if let url {
                continuation.resume(returning: url)
            } else {
                continuation.resume(throwing: error ?? AppError("Sign-in was cancelled."))
            }
        }
    }

    nonisolated(unsafe) private var anchor: ASPresentationAnchor?

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}

/// Guards a continuation against being resumed twice.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
