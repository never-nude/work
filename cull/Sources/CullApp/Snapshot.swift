import AppKit
import CullCore

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

    /// `CULL_PRETEND_DISK=494,11.8` (total and available, in GB) lets a sandbox home be shown
    /// on a nearly full disk, which is the state the app exists for. Ignored outside a sandbox.
    static var pretendDisk: DiskSpace? {
        let parts = (ProcessInfo.processInfo.environment["CULL_PRETEND_DISK"] ?? "")
            .split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] >= 0, parts[1] <= parts[0] else { return nil }
        return DiskSpace(total: Int64(parts[0] * 1e9), free: Int64(parts[1] * 1e9))
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
