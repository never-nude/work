import CullCore
import Foundation

/// Preferences, kept in UserDefaults. Views bind to the same keys with `@AppStorage`.
enum AppSettings {
    enum Key {
        static let staleDays = "staleDays"
        static let projectStaleDays = "projectStaleDays"
        static let downloadsAgeDays = "downloadsAgeDays"
        static let confirmBeforeCulling = "confirmBeforeCulling"
        static let projectRoots = "projectRoots"
        static let exclusions = "exclusions"
        static let hideFullDiskAccessHint = "hideFullDiskAccessHint"
    }

    static let dayChoices = [7, 14, 30, 60, 90, 180]

    private static var defaults: UserDefaults { .standard }

    private static func days(_ key: String, fallback: Int) -> Int {
        let stored = defaults.integer(forKey: key)
        return stored > 0 ? stored : fallback
    }

    static var confirmBeforeCulling: Bool {
        defaults.object(forKey: Key.confirmBeforeCulling) as? Bool ?? true
    }

    /// `nil` means "look in the usual places".
    static var projectRoots: [String]? {
        get { defaults.stringArray(forKey: Key.projectRoots) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.projectRoots)
            } else {
                defaults.removeObject(forKey: Key.projectRoots)
            }
        }
    }

    static var exclusions: [String] {
        get { defaults.stringArray(forKey: Key.exclusions) ?? [] }
        set { defaults.set(newValue, forKey: Key.exclusions) }
    }

    static func addExclusions(_ entries: [String]) {
        var current = exclusions
        for entry in entries where !current.contains(entry) { current.append(entry) }
        exclusions = current
    }

    static var scanOptions: ScanOptions {
        var options = ScanOptions()
        options.staleDays = days(Key.staleDays, fallback: options.staleDays)
        options.projectStaleDays = days(Key.projectStaleDays, fallback: options.projectStaleDays)
        options.downloadsAgeDays = days(Key.downloadsAgeDays, fallback: options.downloadsAgeDays)
        options.projectRoots = projectRoots
        options.exclusions = exclusions
        return options
    }
}
