import Foundation

/// The second key on every deletion.
///
/// Rules decide what is worth culling. This guard decides, independently and from its own
/// lists, whether a path is somewhere Cull is ever allowed to delete. Both have to agree.
/// It is pure string logic on purpose: no filesystem access, so it is easy to test exhaustively.
/// The checks that need the filesystem (symlinks, things changing after the scan) live in `Culler`.
///
/// The shape of the policy:
///  - nothing outside the home folder, and nothing directly inside it;
///  - inside `~/Library`, only an explicit allow list of cache, log, and developer folders;
///  - hidden top-level folders only by allow list (`.npm`, `.cache`, …), so `.ssh` and friends are out;
///  - media folders are out entirely;
///  - in every other folder of yours, exactly two things: a top-level item of `~/Downloads`
///    (to the Trash only), or a folder with a build-artifact name such as `node_modules`;
///  - backups and archives can only be moved to the Trash, never deleted;
///  - no `.git` anywhere in the path;
///  - whatever is left must still sit inside the scope its rule declared.
public struct SafetyGuard: Sendable {
    public let home: String

    public init(home: String) {
        self.home = home
    }

    // MARK: Lists

    /// Top-level folders nothing is ever removed from.
    static let protectedTopLevel: Set<String> = ["pictures", "music", "movies", "applications", "public"]

    /// Folder names a project artifact is allowed to have.
    public static let artifactNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular",
        ".build", "Pods", "target", ".venv", "venv", "DerivedData",
    ]

    /// Cache folders inside a Chromium or Electron profile.
    public static let chromiumCacheNames: [String] = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GrShaderCache", "GraphiteDawnCache", "ShaderCache", "CachedData", "CachedExtensionVSIXs",
        "CachedProfilesData", "Service Worker/CacheStorage", "Service Worker/ScriptCache",
    ]

    /// The only Apple apps whose sandboxed cache may be emptied.
    public static let appleContainersAllowed: Set<String> = [
        "com.apple.safari", "com.apple.music", "com.apple.podcasts", "com.apple.tv",
        "com.apple.news", "com.apple.maps",
    ]

    /// Entries of `~/Library/Caches` that belong to macOS itself and are left alone.
    static let appleCacheNames: Set<String> = [
        "cloudkit", "familycircle", "familycircled", "gamekit", "passkit", "askpermissiond",
        "animoji", "geoservices", "temporaryitems", "storeassetd", "storeaccountd",
        "storedownloadd", "softwareupdate", "icloudmailagent", "knowledge-agent", "siritts",
        "metadata",
    ]

    /// True for caches that belong to macOS. Xcode's (`com.apple.dt.*`) are the exception.
    public static func isAppleOwnedCache(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix("com.apple.dt.") { return false }
        if lower == "com.apple" || lower.hasPrefix("com.apple.") { return true }
        return appleCacheNames.contains(lower)
    }

    // MARK: Paths

    /// `nil` when `action` may be applied to `path`, otherwise the reason it may not.
    public func refusal(for path: String, action: ItemAction, scope: PathScope?) -> String? {
        guard let scope else { return "the rule declared no scope" }
        if case .command = action { return "commands are vetted separately" }
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return "not an absolute path" }
        guard path.hasPrefix(home + "/") else { return "outside the home folder" }

        let relative = String(path.dropFirst(home.count + 1))
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return "path is not normalized"
        }
        guard parts.count >= 2 else { return "too close to the top of the home folder" }

        let first = parts[0]
        let lowerFirst = first.lowercased()
        var isArtifactScope = false
        if case .artifact = scope { isArtifactScope = true }

        if lowerFirst == "library" {
            guard first == "Library" else { return "unexpected spelling of Library" }
            guard !isArtifactScope else { return "nothing in ~/Library is a project artifact" }
            if let reason = libraryRefusal(Array(parts.dropFirst()), action: action) { return reason }
        } else if lowerFirst == ".trash" {
            guard first == ".Trash", parts.count == 2, !isArtifactScope else {
                return "only top-level items in the Trash can be removed"
            }
            guard action == .delete else { return "items in the Trash can only be deleted" }
        } else if first.hasPrefix(".") {
            guard Self.hiddenFolderAllowed(parts), !isArtifactScope else {
                return "~/\(first) is not on the allow list for hidden folders"
            }
        } else {
            if Self.protectedTopLevel.contains(lowerFirst) { return "~/\(first) is protected" }
            if parts.contains(where: { $0.lowercased() == ".git" }) { return "inside Git metadata" }
            if isArtifactScope {
                guard action == .delete else { return "build artifacts are deleted, nothing else" }
            } else {
                // The only loose files Cull ever touches in your own folders.
                guard first == "Downloads", parts.count == 2 else {
                    return "only top-level Downloads items and build artifacts can be removed from your folders"
                }
                guard action == .trash else { return "downloads can only be moved to the Trash" }
            }
        }
        return scopeRefusal(path: path, scope: scope)
    }

    private static func hiddenFolderAllowed(_ parts: [String]) -> Bool {
        switch parts[0] {
        case ".npm":
            return parts.count == 2 && ["_cacache", "_npx", "_logs"].contains(parts[1])
        case ".yarn":
            return parts == [".yarn", "berry", "cache"]
        case ".bun":
            return parts == [".bun", "install", "cache"]
        case ".cache":
            return parts.count >= 2
        case ".gradle":
            return parts == [".gradle", "caches"]
        case ".cargo":
            return parts == [".cargo", "registry", "cache"] || parts == [".cargo", "registry", "src"]
        default:
            return false
        }
    }

    /// `rest` is the path below `~/Library`.
    private func libraryRefusal(_ rest: [String], action: ItemAction) -> String? {
        guard let area = rest.first else { return "~/Library itself is protected" }
        switch area {
        case "Caches":
            guard rest.count >= 2 else { return "the Caches folder itself is protected" }
            if Self.isAppleOwnedCache(rest[1]) { return "\(rest[1]) is a macOS system cache" }
            return nil
        case "Logs":
            return rest.count >= 2 ? nil : "the Logs folder itself is protected"
        case "Developer":
            return developerRefusal(Array(rest.dropFirst()), action: action)
        case "Application Support":
            return applicationSupportRefusal(Array(rest.dropFirst()), action: action)
        case "Containers":
            // Containers/<bundle id>/Data/Library/Caches and nothing else.
            guard rest.count == 5, rest[2] == "Data", rest[3] == "Library", rest[4] == "Caches" else {
                return "only a sandboxed app's Caches folder may be emptied"
            }
            let owner = rest[1].lowercased()
            if owner.hasPrefix("com.apple."), !Self.appleContainersAllowed.contains(owner) {
                return "\(rest[1]) is a macOS system container"
            }
            return nil
        case "iTunes":
            guard rest.count == 2, rest[1].hasSuffix(" Software Updates") else {
                return "not a firmware download folder"
            }
            return nil
        case "pnpm":
            return rest == ["pnpm", "store"] ? nil : "not the pnpm store"
        default:
            return "~/Library/\(area) is not on the allow list"
        }
    }

    /// `rest` is the path below `~/Library/Developer`.
    private func developerRefusal(_ rest: [String], action: ItemAction) -> String? {
        if rest == ["XCTestDevices"] || rest == ["CoreSimulator", "Caches"] { return nil }
        guard rest.count >= 2, rest[0] == "Xcode" else {
            return "~/Library/Developer/\(rest.first ?? "") is not on the allow list"
        }
        let area = rest[1]
        switch area {
        case "DerivedData":
            return rest.count == 3 ? nil : "only individual DerivedData entries may be removed"
        case "Archives":
            guard rest.count == 4, rest[3].hasSuffix(".xcarchive") else {
                return "only individual .xcarchive bundles may be removed"
            }
            return action == .trash ? nil : "archives can only be moved to the Trash"
        case "DocumentationCache", "iOS Device Logs":
            return rest.count == 2 ? nil : "unexpected path inside \(area)"
        case "UserData":
            return rest == ["Xcode", "UserData", "Previews"] ? nil : "only the Previews data may be emptied"
        default:
            if area.hasSuffix(" DeviceSupport") {
                return rest.count == 3 ? nil : "only individual device support folders may be removed"
            }
            return "~/Library/Developer/Xcode/\(area) is not on the allow list"
        }
    }

    /// `rest` is the path below `~/Library/Application Support`.
    private func applicationSupportRefusal(_ rest: [String], action: ItemAction) -> String? {
        guard let owner = rest.first else { return "Application Support itself is protected" }
        if owner == "MobileSync" {
            guard rest.count == 3, rest[1] == "Backup" else { return "only individual device backups may be removed" }
            return action == .trash ? nil : "device backups can only be moved to the Trash"
        }
        if owner.lowercased().hasPrefix("com.apple.") { return "\(owner) belongs to macOS" }
        // <App>/…/<a Chromium cache folder>, at most a couple of profile levels down.
        guard rest.count >= 2, rest.count <= 6 else {
            return "not a recognised cache folder inside Application Support"
        }
        let last = rest[rest.count - 1]
        if Self.chromiumCacheNames.contains(last) { return nil }
        if rest.count >= 3, Self.chromiumCacheNames.contains(rest[rest.count - 2] + "/" + last) { return nil }
        return "not a recognised cache folder inside Application Support"
    }

    private func scopeRefusal(path: String, scope: PathScope) -> String? {
        switch scope {
        case .under(let roots):
            guard !roots.isEmpty, roots.allSatisfy({ $0.hasPrefix(home + "/") }) else {
                return "the rule's folder is outside the home folder"
            }
            return roots.contains { path.hasPrefix($0 + "/") } ? nil : "outside the folder its rule is limited to"
        case .artifact(let root, let names):
            guard root.hasPrefix(home + "/") else { return "the project folder is outside the home folder" }
            guard path.hasPrefix(root + "/") else { return "outside the project folder it was found in" }
            let name = Posix.lastComponent(of: path)
            guard names.contains(name), Self.artifactNames.contains(name) else {
                return "\(name) is not a known build artifact"
            }
            return nil
        }
    }

    // MARK: Commands

    /// `nil` when the command may run. Only three `xcrun simctl` forms pass, each with one UUID.
    public func refusal(forCommand arguments: [String]) -> String? {
        guard arguments.count >= 4, arguments[0] == "/usr/bin/xcrun", arguments[1] == "simctl" else {
            return "only xcrun simctl may be run"
        }
        let rest = Array(arguments.dropFirst(2))
        switch rest[0] {
        case "delete", "erase":
            guard rest.count == 2, UUID(uuidString: rest[1]) != nil else {
                return "simctl \(rest[0]) needs exactly one simulator identifier"
            }
            return nil
        case "runtime":
            guard rest.count == 3, rest[1] == "delete", UUID(uuidString: rest[2]) != nil else {
                return "simctl runtime only accepts delete with one runtime identifier"
            }
            return nil
        default:
            return "simctl \(rest[0]) is not allowed"
        }
    }
}
