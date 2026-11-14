import AppKit

/// Development aid. With `CULL_SNAPSHOT=/path/to.png` set, the app saves a picture of its own
/// window once the first scan has finished, then quits. CI uses it to check the window renders,
/// and it is how the README screenshot is made. `CULL_SNAPSHOT_EXPAND=1` opens every category first.
@MainActor
enum Snapshot {
    static var path: String? {
        let value = ProcessInfo.processInfo.environment["CULL_SNAPSHOT"] ?? ""
        return value.isEmpty ? nil : value
    }

    static var expandsEverything: Bool {
        ProcessInfo.processInfo.environment["CULL_SNAPSHOT_EXPAND"] == "1"
    }

    static func captureAndQuit() {
        guard let path else { return }
        Task { @MainActor in
            // Let the list lay out and the selection animation settle.
            try? await Task.sleep(for: .seconds(2))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
               let view = window.contentView?.superview ?? window.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let data = bitmap.representation(using: .png, properties: [:])
                try? data?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
