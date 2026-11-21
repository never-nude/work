import AppIntents

/// Lets the Action Button (or Siri / Shortcuts) trigger a stream directly.
struct GoLiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Go Live on YouTube"
    static let description = IntentDescription("Opens GoLive and starts streaming to your YouTube channel.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveController.shared.start()
        return .result()
    }
}

struct GoLiveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GoLiveIntent(),
            phrases: ["Go live with \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Go Live",
            systemImageName: "dot.radiowaves.left.and.right"
        )
    }
}
