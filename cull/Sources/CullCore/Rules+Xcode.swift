import Foundation

// Xcode's own leftovers: build data, device symbols, archives.

extension Rule {
    private static let xcodeIdentifiers = ["com.apple.dt.Xcode"]

    /// "MyApp-abcdefghijklmnopqrstuvwxyzab" → "MyApp". Xcode appends a 28-letter hash.
    static func derivedDataProjectName(_ folder: String) -> String {
        guard let dash = folder.lastIndex(of: "-") else { return folder }
        let hash = folder[folder.index(after: dash)...]
        guard hash.count == 28, hash.allSatisfy({ $0.isLowercase && $0.isLetter }), dash != folder.startIndex else {
            return folder
        }
        return String(folder[..<dash])
    }

    private static let sharedDerivedData: [String: String] = [
        "ModuleCache.noindex": "Shared module cache",
        "SymbolCache.noindex": "Symbol cache",
        "CompilationCache.noindex": "Compilation cache",
        "SDKStatCaches.noindex": "SDK stat caches",
    ]

    static let derivedData = Rule(
        id: "xcode.derivedData",
        title: "Xcode DerivedData",
        blurb: "Build products and indexes, one folder per project. Xcode rebuilds them the next time the project is opened.",
        tier: .rebuildable,
        symbol: "hammer",
        detect: { context in
            guard let root = context.directory("Library/Developer/Xcode/DerivedData") else { return [] }
            let xcodeRunning = context.env.runningApp(matching: xcodeIdentifiers) != nil
            return context.children(of: root).compactMap { child in
                guard child.stat.kind == .directory, !child.name.hasPrefix(".") else { return nil }
                if child.name.hasSuffix(".noindex") {
                    // Shared between every project, so pulling it out from under a running build hurts.
                    return Candidate(
                        key: child.name,
                        title: sharedDerivedData[child.name] ?? child.name,
                        subtitle: "Shared by all projects",
                        paths: [child.path],
                        action: .delete,
                        scope: .under([root]),
                        policy: xcodeRunning ? .never : .always,
                        caution: xcodeRunning ? "Xcode is running" : nil
                    )
                }
                var subtitle: String?
                if let info = context.propertyList(at: child.path + "/info.plist"),
                   let workspace = info["WorkspacePath"] as? String {
                    subtitle = context.tilde(workspace)
                }
                return Candidate(
                    key: child.name,
                    title: derivedDataProjectName(child.name),
                    subtitle: subtitle,
                    paths: [child.path],
                    action: .delete,
                    scope: .under([root]),
                    policy: .staleTree(days: context.options.staleDays),
                    lastUsedLabel: "Last built"
                )
            }
        }
    )

    static let deviceSupport = Rule(
        id: "xcode.deviceSupport",
        title: "Device support files",
        blurb: "Debug symbols Xcode copied from each OS version of every device you have plugged in. Copied again when a device reconnects.",
        tier: .rebuildable,
        symbol: "cable.connector",
        detect: { context in
            guard let xcode = context.directory("Library/Developer/Xcode") else { return [] }
            var found: [Candidate] = []
            for platform in context.children(of: xcode)
            where platform.stat.kind == .directory && platform.name.hasSuffix(" DeviceSupport") {
                let platformName = String(platform.name.dropLast(" DeviceSupport".count))
                let versions = context.children(of: platform.path).filter {
                    $0.stat.kind == .directory && !$0.name.hasPrefix(".")
                }
                // The newest one is almost certainly the device on your desk right now.
                let newest = versions.max { $0.stat.modified < $1.stat.modified }?.name
                for version in versions {
                    let keep = version.name == newest
                    found.append(Candidate(
                        key: platform.name + "/" + version.name,
                        title: "\(platformName) \(version.name)",
                        subtitle: keep ? "Newest, so left unselected" : nil,
                        paths: [version.path],
                        action: .delete,
                        scope: .under([platform.path]),
                        policy: keep ? .never : .always,
                        lastUsed: version.stat.modified,
                        lastUsedLabel: "Copied"
                    ))
                }
            }
            return found
        }
    )

    static let xcodeCaches = Rule(
        id: "caches.xcode",
        title: "Xcode & Simulator caches",
        blurb: "Xcode's download and index caches, simulator caches and logs, and the documentation cache.",
        tier: .safe,
        symbol: "wrench.and.screwdriver",
        claims: ["Library/Logs/CoreSimulator"],
        detect: { context in
            var found: [Candidate] = []
            let xcodeRunning = context.env.runningApp(matching: xcodeIdentifiers) != nil
            if let caches = context.directory("Library/Caches") {
                let paths = context.children(of: caches)
                    .filter { $0.stat.kind == .directory && $0.name.lowercased().hasPrefix("com.apple.dt.") }
                    .map(\.path)
                if !paths.isEmpty {
                    found.append(Candidate(
                        key: "xcode", title: "Xcode caches", subtitle: "~/Library/Caches/com.apple.dt.*",
                        paths: paths, action: .deleteContents, scope: .under([caches]),
                        policy: xcodeRunning ? .never : .always,
                        caution: xcodeRunning ? "Xcode is running" : nil
                    ))
                }
            }
            let fixed: [(String, String)] = [
                ("Simulator caches", "Library/Developer/CoreSimulator/Caches"),
                ("Simulator logs", "Library/Logs/CoreSimulator"),
                ("Documentation cache", "Library/Developer/Xcode/DocumentationCache"),
                ("Device logs", "Library/Developer/Xcode/iOS Device Logs"),
            ]
            for (label, relative) in fixed {
                guard let path = context.directory(relative) else { continue }
                found.append(Candidate(
                    key: relative, title: label, subtitle: context.tilde(path), paths: [path],
                    action: .deleteContents, scope: .under([Posix.parent(of: path)])
                ))
            }
            return found
        }
    )

    static let previews = Rule(
        id: "xcode.previews",
        title: "Preview & test simulators",
        blurb: "Throwaway simulators Xcode keeps for SwiftUI previews and test runs. It makes new ones on demand.",
        tier: .rebuildable,
        symbol: "rectangle.on.rectangle",
        detect: { context in
            let xcodeRunning = context.env.runningApp(matching: xcodeIdentifiers) != nil
            let fixed: [(String, String)] = [
                ("SwiftUI preview data", "Library/Developer/Xcode/UserData/Previews"),
                ("Test simulators", "Library/Developer/XCTestDevices"),
            ]
            return fixed.compactMap { label, relative in
                guard let path = context.directory(relative) else { return nil }
                return Candidate(
                    key: relative, title: label, subtitle: context.tilde(path), paths: [path],
                    action: .deleteContents, scope: .under([Posix.parent(of: path)]),
                    policy: xcodeRunning ? .never : .always,
                    caution: xcodeRunning ? "Xcode is running" : nil
                )
            }
        }
    )

    static let archives = Rule(
        id: "xcode.archives",
        title: "Xcode archives",
        blurb: "Builds from Product › Archive. They hold the debug symbols for whatever you shipped, so keep the ones behind live releases.",
        tier: .review,
        symbol: "archivebox.circle",
        detect: { context in
            guard let root = context.directory("Library/Developer/Xcode/Archives") else { return [] }
            var found: [Candidate] = []
            for day in context.children(of: root) where day.stat.kind == .directory {
                for archive in context.children(of: day.path)
                where archive.stat.kind == .directory && archive.name.hasSuffix(".xcarchive") {
                    found.append(Candidate(
                        key: day.name + "/" + archive.name,
                        title: String(archive.name.dropLast(".xcarchive".count)),
                        subtitle: context.tilde(archive.path),
                        paths: [archive.path],
                        action: .trash,
                        scope: .under([root]),
                        policy: .never,
                        lastUsed: archive.stat.modified,
                        lastUsedLabel: "Archived"
                    ))
                }
            }
            return found
        }
    )
}
