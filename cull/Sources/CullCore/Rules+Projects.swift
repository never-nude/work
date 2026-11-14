import Foundation

// Dependencies and build output sitting in projects nobody has opened in a while.

struct ProjectScanner {
    let context: RuleContext

    /// Folders under home that commonly hold projects. Only the ones that exist are searched.
    static let defaultRoots = [
        "Developer", "Projects", "projects", "Code", "code", "Coding", "dev", "Dev", "src", "Source",
        "repos", "Repos", "Repositories", "git", "Git", "GitHub", "github", "workspace", "Workspace",
        "work", "Work", "Sites", "sites", "Xcode", "apps", "Apps", "Documents", "Desktop",
    ]

    static let maximumDepth = 6
    static let maximumDirectories = 200_000

    /// Folders never worth walking into while looking for projects.
    static let skippedNames: Set<String> = [
        "node_modules", "bower_components", "Pods", "Carthage", "DerivedData", "build", "dist", "target",
        "vendor", "venv", "site-packages", "__pycache__", "Library", "Applications", "Pictures", "Music",
        "Movies",
    ]

    /// Bundles and libraries that look like folders but are really documents.
    static let skippedExtensions: Set<String> = [
        "app", "framework", "xcframework", "bundle", "plugin", "kext", "xcodeproj", "xcworkspace",
        "xcassets", "xcarchive", "dsym", "playground", "docc", "scnassets", "lproj", "rtfd",
        "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band",
        "sparsebundle", "pkg", "mpkg", "vmwarevm", "pvm", "utm", "key", "pages", "numbers",
    ]

    static func shouldDescend(_ name: String) -> Bool {
        if name.hasPrefix(".") || skippedNames.contains(name) { return false }
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let ext = name[name.index(after: dot)...].lowercased()
            if skippedExtensions.contains(ext) { return false }
        }
        return true
    }

    struct Artifact {
        let name: String
        let path: String
        /// False when there is nothing on disk that pins how to bring it back.
        let restorable: Bool
        let warning: String?
    }

    private static let nodeLockfiles = [
        "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock", "npm-shrinkwrap.json",
    ]
    private static let nodeBuildCaches = [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular"]
    /// A requirements.txt does not count: it rarely lists everything that was installed by hand.
    private static let pythonLockfiles = ["uv.lock", "poetry.lock", "Pipfile.lock", "pdm.lock"]

    /// Build artifacts in `children`, each identified by a neighbour that proves what it is.
    /// A folder merely named `node_modules` or `target` with no manifest beside it is ignored.
    static func artifacts(
        children: [RuleContext.Child], names: Set<String>, lockedAbove: Bool, context: RuleContext
    ) -> [Artifact] {
        var result: [Artifact] = []
        func folder(_ name: String) -> RuleContext.Child? {
            children.first { $0.name == name && $0.stat.kind == .directory }
        }

        if names.contains("package.json") {
            if let found = folder("node_modules") {
                let locked = lockedAbove || nodeLockfiles.contains(where: names.contains)
                result.append(Artifact(
                    name: found.name, path: found.path, restorable: locked,
                    warning: locked ? nil : "No lockfile; reinstalling may resolve different versions"
                ))
            }
            for name in nodeBuildCaches {
                if let found = folder(name) {
                    result.append(Artifact(name: found.name, path: found.path, restorable: true, warning: nil))
                }
            }
        }
        if names.contains("Package.swift"), let found = folder(".build") {
            result.append(Artifact(name: found.name, path: found.path, restorable: true, warning: nil))
        }
        if names.contains("Podfile"), let found = folder("Pods") {
            let locked = names.contains("Podfile.lock")
            result.append(Artifact(
                name: found.name, path: found.path, restorable: locked,
                warning: locked ? nil : "No Podfile.lock; reinstalling may resolve different versions"
            ))
        }
        if names.contains("Cargo.toml"), let found = folder("target"),
           context.exists(found.path + "/CACHEDIR.TAG") || context.isDirectory(found.path + "/debug")
            || context.isDirectory(found.path + "/release") {
            result.append(Artifact(name: found.name, path: found.path, restorable: true, warning: nil))
        }
        for name in [".venv", "venv"] {
            if let found = folder(name), context.exists(found.path + "/pyvenv.cfg") {
                let locked = pythonLockfiles.contains(where: names.contains)
                result.append(Artifact(
                    name: found.name, path: found.path, restorable: locked,
                    warning: locked ? nil : "No lockfile; packages installed by hand would be lost"
                ))
            }
        }
        let isXcodeProject = names.contains("Package.swift")
            || names.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
        if isXcodeProject, let found = folder("DerivedData") {
            result.append(Artifact(name: found.name, path: found.path, restorable: true, warning: nil))
        }
        return result
    }

    /// A lockfile vouches for packages nested below it only when its folder says they are
    /// its workspace. A stray `package-lock.json` in ~/Developer must not make every project
    /// underneath look exactly restorable.
    static func declaresWorkspace(_ directory: String, names: Set<String>) -> Bool {
        if names.contains("pnpm-workspace.yaml") { return true }
        guard names.contains("package.json"),
              let data = FileManager.default.contents(atPath: directory + "/package.json"), data.count < 4_000_000,
              let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return manifest["workspaces"] != nil
    }

    static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return max(lhs, rhs)
    }

    /// When Git last did anything in this repository.
    static func gitActivity(in project: String) -> Date? {
        let git = project + "/.git"
        guard Posix.info(at: git)?.kind == .directory else { return nil }
        var newest: Date?
        for name in ["HEAD", "index", "FETCH_HEAD", "ORIG_HEAD", "logs/HEAD"] {
            if let stat = Posix.info(at: git + "/" + name), stat.kind == .file {
                newest = latest(newest, stat.modified)
            }
        }
        return newest
    }

    /// Best estimate of when someone last worked on a project: the newest of its top-level
    /// entries, its Git activity, and a bounded look into its source folders (editing a file
    /// does not touch the folders above it).
    static func lastActivity(
        children: [RuleContext.Child], artifactNames: Set<String>, gitActivity: Date?
    ) -> Date? {
        var newest = gitActivity
        var queue: [(path: String, depth: Int)] = []
        for child in children where child.name != ".DS_Store" && child.stat.kind != .symlink {
            newest = latest(newest, child.stat.modified)
            if child.stat.kind == .directory, !artifactNames.contains(child.name), shouldDescend(child.name) {
                queue.append((child.path, 1))
            }
        }
        // Breadth first, so a busy folder near the top cannot use up the whole budget before
        // the others are looked at. Folder times count too: adding or removing a file is work.
        var budget = 6_000
        var index = 0
        while budget > 0, index < queue.count {
            let next = queue[index]
            index += 1
            Posix.forEachEntry(in: next.path) { name, fd in
                guard budget > 0, let stat = Posix.info(named: name, in: fd) else { return }
                budget -= 1
                guard stat.kind == .file || stat.kind == .directory else { return }
                newest = latest(newest, stat.modified)
                if stat.kind == .directory, next.depth < 6 {
                    let childName = String(cString: name)
                    if shouldDescend(childName) { queue.append((Posix.join(next.path, childName), next.depth + 1)) }
                }
            }
        }
        return newest
    }

    /// Canonical, de-duplicated search roots, all strictly inside home.
    func roots() -> [String] {
        let requested: [String]
        if let custom = context.options.projectRoots {
            requested = custom.map { raw in
                var path = raw
                if path == "~" { path = context.home } else if path.hasPrefix("~/") { path = context.home + path.dropFirst(1) }
                while path.count > 1, path.hasSuffix("/") { path.removeLast() }
                return path
            }
        } else {
            requested = Self.defaultRoots.map(context.path)
        }

        var seen = Set<FileIdentity>()
        var roots: [String] = []
        for candidate in requested {
            guard let real = context.directory(atPath: candidate), let stat = Posix.info(at: real) else { continue }
            // Nothing in ~/Library, a hidden folder or a media folder is a project, and the
            // safety guard would refuse whatever was found there anyway.
            let top = real.dropFirst(context.home.count + 1).split(separator: "/").first.map(String.init) ?? ""
            if top == "Library" || top.hasPrefix(".") || SafetyGuard.protectedTopLevel.contains(top.lowercased()) {
                continue
            }
            guard seen.insert(FileIdentity(device: stat.device, inode: stat.inode)).inserted else { continue }
            roots.append(real)
        }
        // A root inside another root would be walked twice.
        return roots.filter { root in
            !roots.contains { other in other != root && root.hasPrefix(other + "/") }
        }
    }

    func run() -> [Candidate] {
        var found: [Candidate] = []
        var visited = 0
        let staleDays = context.options.projectStaleDays

        for root in roots() {
            guard let rootStat = Posix.info(at: root) else { continue }
            var stack: [(path: String, depth: Int, gitActivity: Date?, locked: Bool)] = [(root, 0, nil, false)]

            while let frame = stack.popLast() {
                visited += 1
                if visited > Self.maximumDirectories { return found }

                let children = context.children(of: frame.path)
                if children.isEmpty { continue }
                let names = Set(children.map(\.name))

                var gitActivity = frame.gitActivity
                if names.contains(".git") {
                    gitActivity = Self.latest(gitActivity, Self.gitActivity(in: frame.path))
                }
                let locked = frame.locked
                    || (names.contains("package.json") && Self.nodeLockfiles.contains(where: names.contains)
                        && Self.declaresWorkspace(frame.path, names: names))

                let artifacts = Self.artifacts(
                    children: children, names: names, lockedAbove: frame.locked, context: context
                )
                let artifactNames = Set(artifacts.map(\.name))
                if !artifacts.isEmpty {
                    let activity = Self.lastActivity(
                        children: children, artifactNames: artifactNames, gitActivity: gitActivity
                    )
                    let project = Posix.lastComponent(of: frame.path)
                    for artifact in artifacts {
                        found.append(Candidate(
                            key: artifact.path,
                            title: "\(project) · \(artifact.name)",
                            subtitle: context.tilde(frame.path),
                            paths: [artifact.path],
                            action: .delete,
                            scope: .artifact(root: root, names: [artifact.name]),
                            policy: artifact.restorable ? .staleProject(activity, days: staleDays) : .never,
                            caution: artifact.warning,
                            lastUsed: activity,
                            lastUsedLabel: "Project last touched"
                        ))
                    }
                }

                guard frame.depth < Self.maximumDepth else { continue }
                for child in children
                where child.stat.kind == .directory && child.stat.device == rootStat.device {
                    if artifactNames.contains(child.name) || !Self.shouldDescend(child.name) { continue }
                    stack.append((child.path, frame.depth + 1, gitActivity, locked))
                }
            }
        }
        return found
    }
}

extension Rule {
    static let projectArtifacts = Rule(
        id: "projects.artifacts",
        title: "Stale project dependencies & builds",
        blurb: "node_modules, .build, Pods, virtual environments and build caches in projects you have not touched lately. A reinstall or rebuild brings them back.",
        tier: .rebuildable,
        symbol: "folder.badge.gearshape",
        detect: { context in ProjectScanner(context: context).run() }
    )
}
