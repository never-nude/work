import AVFoundation
import Foundation

enum Privacy: String, CaseIterable, Identifiable {
    case `public`, unlisted, `private`
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Quality: String, CaseIterable, Identifiable {
    case hd720, hd1080
    var id: String { rawValue }
    var label: String { self == .hd720 ? "720p" : "1080p" }
    var preset: AVCaptureSession.Preset { self == .hd720 ? .hd1280x720 : .hd1920x1080 }
    var longSide: Int { self == .hd720 ? 1280 : 1920 }
    var shortSide: Int { self == .hd720 ? 720 : 1080 }
    var bitrate: Int { self == .hd720 ? 4_000_000 : 6_000_000 }
}

/// How hard the camera smooths out hand shake. Stronger modes crop more of the frame and
/// hold each frame back longer before it can be sent.
enum Stabilization: String, CaseIterable, Identifiable, Sendable {
    case off, standard, strong, maximum
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .standard: return "Standard"
        case .strong: return "Strong"
        case .maximum: return "Maximum"
        }
    }

    /// Modes to try, best first; the first one the camera's current format supports wins.
    var candidates: [AVCaptureVideoStabilizationMode] {
        switch self {
        case .off:
            return []
        case .standard:
            return [.standard]
        case .strong:
            return [.cinematic, .standard]
        case .maximum:
            if #available(iOS 18.0, *) {
                return [.cinematicExtendedEnhanced, .cinematicExtended, .cinematic, .standard]
            }
            return [.cinematicExtended, .cinematic, .standard]
        }
    }

    func bestMode(for device: AVCaptureDevice?) -> AVCaptureVideoStabilizationMode {
        guard let format = device?.activeFormat else { return .off }
        return candidates.first(where: { format.isVideoStabilizationModeSupported($0) }) ?? .off
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Everything the app remembers between launches. Tokens live in the Keychain, not here.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    /// The number the next broadcast will be titled with ("Live stream N").
    @Published var nextNumber: Int { didSet { defaults.set(nextNumber, forKey: "nextNumber") } }
    @Published var privacy: Privacy { didSet { defaults.set(privacy.rawValue, forKey: "privacy") } }
    @Published var quality: Quality { didSet { defaults.set(quality.rawValue, forKey: "quality") } }
    @Published var goLiveOnOpen: Bool { didSet { defaults.set(goLiveOnOpen, forKey: "goLiveOnOpen") } }
    @Published var useFrontCamera: Bool { didSet { defaults.set(useFrontCamera, forKey: "useFrontCamera") } }
    @Published var stabilization: Stabilization { didSet { defaults.set(stabilization.rawValue, forKey: "stabilization") } }
    @Published var clientID: String { didSet { defaults.set(clientID, forKey: "clientID") } }
    @Published var channelTitle: String { didSet { defaults.set(channelTitle, forKey: "channelTitle") } }

    // Reusable YouTube ingest point, cached so launches skip one API round trip.
    var streamID: String? {
        get { defaults.string(forKey: "streamID") }
        set { defaults.set(newValue, forKey: "streamID") }
    }
    var ingestURL: String? {
        get { defaults.string(forKey: "ingestURL") }
        set { defaults.set(newValue, forKey: "ingestURL") }
    }
    var streamKey: String? {
        get { defaults.string(forKey: "streamKey") }
        set { defaults.set(newValue, forKey: "streamKey") }
    }

    private init() {
        nextNumber = max(1, defaults.object(forKey: "nextNumber") as? Int ?? 1)
        privacy = Privacy(rawValue: defaults.string(forKey: "privacy") ?? "") ?? .public
        quality = Quality(rawValue: defaults.string(forKey: "quality") ?? "") ?? .hd720
        goLiveOnOpen = defaults.object(forKey: "goLiveOnOpen") as? Bool ?? true
        useFrontCamera = defaults.bool(forKey: "useFrontCamera")
        stabilization = Stabilization(rawValue: defaults.string(forKey: "stabilization") ?? "") ?? .strong
        channelTitle = defaults.string(forKey: "channelTitle") ?? ""
        let baked = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String) ?? ""
        let saved = defaults.string(forKey: "clientID") ?? ""
        clientID = saved.isEmpty ? baked : saved
    }

    func forgetStream() {
        streamID = nil
        ingestURL = nil
        streamKey = nil
    }
}
