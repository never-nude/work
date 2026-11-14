import Foundation

#if os(macOS)
import CoreServices
#endif

// Personal files. Nothing here is ever pre-selected, and files go to the Trash.

enum FileDates {
    /// The most recent sign that anyone cared about a file: modified, created,
    /// added to its folder, or (on macOS) last opened.
    static func lastTouched(path: String, stat: FileStat) -> Date {
        var newest = stat.modified
        if let created = stat.created, created > newest { newest = created }
        #if os(macOS)
        let url = URL(fileURLWithPath: path)
        if let added = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate,
           added > newest {
            newest = added
        }
        if let opened = lastOpened(path), opened > newest { newest = opened }
        #endif
        return newest
    }

    #if os(macOS)
    /// Finder's "Date Last Opened", when Spotlight knows it.
    static func lastOpened(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
    #endif

    static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}

extension Rule {
    static let trash = Rule(
        id: "trash",
        title: "Trash",
        blurb: "Everything sitting in your Trash. Unlike the rest of this section, emptying it is permanent.",
        tier: .review,
        symbol: "trash",
        needsFullDiskAccess: true,
        detect: { context in
            guard let trash = context.directory(".Trash") else { return [] }
            let children = context.children(of: trash).filter { $0.name != ".DS_Store" }
            guard !children.isEmpty else { return [] }
            return [Candidate(
                key: "all",
                title: "Everything in the Trash",
                subtitle: Format.count(children.count, "item"),
                paths: children.map(\.path),
                action: .delete,
                scope: .under([trash]),
                policy: .never,
                minimumBytes: 0
            )]
        }
    )

    private static let partialDownloads: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp"]
    private static let installers: Set<String> = ["dmg", "pkg", "mpkg", "xip", "ipsw", "iso"]

    static let oldDownloads = Rule(
        id: "downloads.old",
        title: "Old downloads",
        blurb: "Things in ~/Downloads that have not been added, changed or opened in a long while, plus installers you have most likely already run.",
        tier: .review,
        symbol: "arrow.down.to.line",
        detect: { context in
            guard let downloads = context.directory("Downloads") else { return [] }
            return context.children(of: downloads).compactMap { child in
                guard child.stat.kind == .file || child.stat.kind == .directory, !child.name.hasPrefix(".") else {
                    return nil
                }
                let ext = FileDates.fileExtension(child.name)
                if partialDownloads.contains(ext) { return nil }
                let isInstaller = installers.contains(ext)
                let touched = FileDates.lastTouched(path: child.path, stat: child.stat)
                // An installer has done its job within a couple of weeks.
                let threshold = isInstaller ? min(14, context.options.downloadsAgeDays) : context.options.downloadsAgeDays
                guard context.days(since: touched) >= Double(threshold) else { return nil }
                return Candidate(
                    key: child.name,
                    title: child.name,
                    subtitle: isInstaller ? "Installer" : nil,
                    paths: [child.path],
                    action: .trash,
                    scope: .under([downloads]),
                    policy: .never,
                    lastUsed: touched,
                    lastUsedLabel: "Last touched"
                )
            }
        }
    )

    static let deviceBackups = Rule(
        id: "ios.backups",
        title: "iPhone & iPad backups",
        blurb: "Local backups made through Finder. Each is a full copy of a device, so only let go of ones that are stale or duplicated in iCloud.",
        tier: .review,
        symbol: "iphone",
        needsFullDiskAccess: true,
        detect: { context in
            guard let root = context.directory("Library/Application Support/MobileSync/Backup") else { return [] }
            return context.children(of: root).compactMap { child in
                guard child.stat.kind == .directory, !child.name.hasPrefix(".") else { return nil }
                let info = context.propertyList(at: child.path + "/Info.plist")
                let device = (info?["Device Name"] as? String) ?? (info?["Display Name"] as? String) ?? child.name
                return Candidate(
                    key: child.name,
                    title: device,
                    subtitle: info?["Product Name"] as? String,
                    paths: [child.path],
                    action: .trash,
                    scope: .under([root]),
                    policy: .never,
                    lastUsed: (info?["Last Backup Date"] as? Date) ?? child.stat.modified,
                    lastUsedLabel: "Backed up"
                )
            }
        }
    )
}
