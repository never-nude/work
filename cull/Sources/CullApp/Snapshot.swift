import AppKit
import CullCore

/// Development aid. With `CULL_SNAPSHOT=/path/to.png` set, the app saves a picture of its own
/// window once the first scan has finished, then quits. CI uses it to check the window renders,
/// and it is how the README screenshot is made. `CULL_SNAPSHOT_EXPAND=1` opens every category first.
/// None of this does anything unless `CULL_SNAPSHOT` is set.
@MainActor
enum Snapshot {
    static var path: String? {
        let value = ProcessInfo.processInfo.environment["CULL_SNAPSHOT"] ?? ""
        return value.isEmpty ? nil : value
    }

    static var expandsEverything: Bool {
        ProcessInfo.processInfo.environment["CULL_SNAPSHOT_EXPAND"] == "1"
    }

    /// `CULL_SNAPSHOT_SCROLL=review` starts the list at a tier (`safe`, `rebuildable`, `review`) or at `footer`.
    static var scrollTarget: String? {
        let value = ProcessInfo.processInfo.environment["CULL_SNAPSHOT_SCROLL"] ?? ""
        return path == nil || value.isEmpty ? nil : value
    }

    /// `CULL_SNAPSHOT_SETTINGS=1` opens the Settings window and photographs that instead.
    static var showsSettings: Bool {
        path != nil && ProcessInfo.processInfo.environment["CULL_SNAPSHOT_SETTINGS"] == "1"
    }

    /// `CULL_SNAPSHOT_CULL=1` culls the pre-selected items first, so the picture shows the result.
    /// The model only honours it for a sandbox home.
    static var cullsFirst: Bool {
        path != nil && ProcessInfo.processInfo.environment["CULL_SNAPSHOT_CULL"] == "1"
    }

    /// `CULL_SNAPSHOT_DARK=1` takes the picture in dark mode.
    static var usesDarkAppearance: Bool {
        ProcessInfo.processInfo.environment["CULL_SNAPSHOT_DARK"] == "1"
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
        if usesDarkAppearance { NSApp.appearance = NSAppearance(named: .darkAqua) }
        Task { @MainActor in
            // Let the list lay out and the selection animation settle.
            try? await Task.sleep(for: .seconds(2))
            let visible = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
            let isSettings: (NSWindow) -> Bool = { window in
                (window.identifier?.rawValue ?? "").localizedCaseInsensitiveContains("settings")
                    || window.title.localizedCaseInsensitiveContains("settings")
            }
            let chosen = showsSettings ? visible.first(where: isSettings) : visible.first { !isSettings($0) }
            if let window = chosen ?? visible.first,
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
