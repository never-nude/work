import AppKit

/// Turns a cache folder's name ("com.tinyspeck.slackmacgap", "Slack") into the app it belongs to.
@MainActor
final class AppIdentity {
    static let shared = AppIdentity()

    struct Info {
        let name: String?
        let icon: NSImage?
    }

    private var cache: [String: Info] = [:]

    func info(for title: String) -> Info {
        if let cached = cache[title] { return cached }
        var location: URL?
        if title.contains(".") {
            location = NSWorkspace.shared.urlForApplication(withBundleIdentifier: title)
        }
        if location == nil {
            for folder in ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications"] {
                let candidate = URL(fileURLWithPath: folder).appendingPathComponent(title + ".app")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    location = candidate
                    break
                }
            }
        }
        let info: Info
        if let location {
            var name = FileManager.default.displayName(atPath: location.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            info = Info(name: name, icon: NSWorkspace.shared.icon(forFile: location.path))
        } else {
            info = Info(name: nil, icon: nil)
        }
        cache[title] = info
        return info
    }
}
