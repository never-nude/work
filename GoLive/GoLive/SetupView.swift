import SwiftUI
import UIKit

/// One-time connection to the YouTube channel.
struct SetupView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var auth: GoogleAuth
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.red)
                    Text("GoLive")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                    Text("Connect your YouTube channel once. After that, opening the app is the broadcast.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Google OAuth client ID", systemImage: "1.circle.fill")
                        .font(.headline)
                    HStack(spacing: 10) {
                        TextField("…apps.googleusercontent.com", text: $settings.clientID, axis: .vertical)
                            .font(.system(.footnote, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(1...3)
                        Button("Paste") {
                            if let text = UIPasteboard.general.string { settings.clientID = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .padding(14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    Text("The iOS-type client ID from your Google Cloud project. The README in this project walks through creating it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Sign in", systemImage: "2.circle.fill")
                        .font(.headline)
                    Button(action: signIn) {
                        HStack {
                            if working { ProgressView().tint(.white) }
                            Text(working ? "Waiting for Google" : "Sign in with Google")
                                .font(.system(.headline, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.red, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                    }
                    .disabled(working || !GoogleAuth.isPlausible(settings.clientID))
                    .opacity(GoogleAuth.isPlausible(settings.clientID) ? 1 : 0.4)
                    Text("Pick the Google account that owns the channel. If it has more than one channel, Google asks which.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func signIn() {
        problem = nil
        working = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task {
            defer { working = false }
            do {
                try await auth.signIn()
                // Confirms the account really has a channel and remembers its name.
                do {
                    settings.channelTitle = try await YouTubeAPI(token: auth.validToken()).channelTitle()
                } catch {
                    auth.signOut()
                    throw error
                }
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
