import AppKit
import SwiftUI

@main
struct CullApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Cull", id: "main") {
            ContentView()
                .environment(model)
                .tint(Theme.accent)
        }
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Scan Again") { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
                Button("Cull Selected…") { model.requestCull() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canCull)
                Divider()
                Button("Select Recommended") { model.selectRecommended() }
                    .keyboardShortcut("d")
                    .disabled(model.report == nil)
                Button("Select Nothing") { model.selectNothing() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(model.report == nil)
                Divider()
                Button("Expand All") { model.expandAll() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Collapse All") { model.collapseAll() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.accent)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets `swift run CullApp` behave like a real app during development.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Snapshot.applyRequestedAppearance()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
