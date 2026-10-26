import AppKit
import SwiftUI

@main
struct LoopsmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var studio = Studio()

    var body: some Scene {
        WindowGroup("Loopsmith") {
            ContentView()
                .environment(studio)
                .frame(minWidth: 720, minHeight: 540)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") { studio.openVideoPanel() }
                    .keyboardShortcut("o")
                Button("Record Screen…") { studio.showRecorder = true }
                    .keyboardShortcut("r")
                    .disabled(studio.isRecording)
                Button("Stop Recording") { Task { await studio.stopRecording() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!studio.isRecording)
                Divider()
                Button("Export GIF…") { studio.exportPanel() }
                    .keyboardShortcut("e")
                    .disabled(studio.asset == nil || studio.isExporting)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
