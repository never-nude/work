import Foundation

/// How an item decides whether it is pre-selected.
enum SelectionPolicy: Sendable {
    case always
    case never
    /// Selected once nothing inside the item has changed for `days`.
    case staleTree(days: Int)
    /// Selected once `date` is at least `days` old. An unknown date is never stale.
    case staleSince(Date?, days: Int)
}

/// Something a rule found, before it has been weighed.
struct Candidate: Sendable {
    /// Unique within its rule.
    var key: String
    var title: String
    var subtitle: String?
    var paths: [String] = []
    var action: ItemAction
    var scope: PathScope?
    var policy: SelectionPolicy = .always
    var caution: String?
    var lastUsed: Date?
    var lastUsedLabel: String?
    /// Size known without walking (simulator runtimes report their own).
    var fixedBytes: Int64?
    /// Paths to weigh when they are not `paths` (command-backed items).
    var measuredPaths: [String]?
    /// Overrides the usual "too small to list" threshold.
    var minimumBytes: Int64?
}

struct Rule: Sendable {
    let id: String
    let title: String
    let blurb: String
    let tier: Tier
    let symbol: String
    var needsFullDiskAccess = false
    /// Home-relative paths this rule owns, so the catch-all cache rules leave them alone.
    var claims: [String] = []
    let detect: @Sendable (RuleContext) -> [Candidate]
}

/// Results worth computing once per scan, shared between rules.
final class ScanMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func value<T>(_ key: String, compute: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if let cached = values[key] as? T { return cached }
        let fresh = compute()
        values[key] = fresh
        return fresh
    }
}

struct RuleContext: Sendable {
    let env: CullEnvironment
    let options: ScanOptions
    /// Lowercased home-relative paths owned by specific rules.
    let claimed: Set<String>
    let memo: ScanMemo

    var home: String { env.home }

    func path(_ relative: String) -> String {
        Posix.join(env.home, relative)
    }

    func tilde(_ path: String) -> String {
        Format.tilde(path, home: env.home)
    }

    /// The canonical path of `relative`, but only when it is a real directory reached
    /// without passing through a symlink. Relocated folders are deliberately invisible.
    func directory(_ relative: String) -> String? {
        directory(atPath: path(relative))
    }

    func directory(atPath lexical: String) -> String? {
        guard Posix.info(at: lexical)?.kind == .directory, let real = Posix.realPath(lexical) else { return nil }
        // Case may legitimately differ on a case-insensitive volume. Anything else is a detour.
        guard real.lowercased() == lexical.lowercased(), real.hasPrefix(env.home + "/") else { return nil }
        return real
    }

    struct Child: Sendable {
        let name: String
        let path: String
        let stat: FileStat
    }

    /// Direct children of `directory`, described without following symlinks.
    func children(of directory: String) -> [Child] {
        guard let names = Posix.entries(of: directory) else { return [] }
        return names.compactMap { name in
            let childPath = Posix.join(directory, name)
            guard let stat = Posix.info(at: childPath) else { return nil }
            return Child(name: name, path: childPath, stat: stat)
        }
    }

    func exists(_ path: String) -> Bool {
        Posix.info(at: path) != nil
    }

    func isDirectory(_ path: String) -> Bool {
        Posix.info(at: path)?.kind == .directory
    }

    /// True when a specific rule owns this home-relative path or something inside it.
    func isClaimed(_ relative: String) -> Bool {
        let lower = relative.lowercased()
        if claimed.contains(lower) { return true }
        let prefix = lower + "/"
        return claimed.contains { $0.hasPrefix(prefix) }
    }

    func days(since date: Date) -> Double {
        env.now.timeIntervalSince(date) / 86_400
    }

    func propertyList(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}

extension Rule {
    struct Location: Sendable {
        let label: String
        /// Home-relative directories whose contents make up this item.
        let paths: [String]
        /// Apps that should be quit first.
        var apps: [String] = []
        var policy: SelectionPolicy = .always
    }

    /// A rule made of well-known directories. Each location becomes one item whose contents are emptied.
    static func locations(
        id: String, title: String, blurb: String, tier: Tier, symbol: String,
        needsFullDiskAccess: Bool = false, _ locations: [Location]
    ) -> Rule {
        Rule(
            id: id, title: title, blurb: blurb, tier: tier, symbol: symbol,
            needsFullDiskAccess: needsFullDiskAccess,
            claims: locations.flatMap(\.paths),
            detect: { context in
                locations.compactMap { location in
                    let found = location.paths.compactMap { context.directory($0) }
                    guard !found.isEmpty else { return nil }
                    var policy = location.policy
                    var caution: String?
                    if let running = context.env.runningApp(matching: location.apps) {
                        policy = .never
                        caution = "\(running) is running"
                    }
                    return Candidate(
                        key: location.label,
                        title: location.label,
                        subtitle: found.map(context.tilde).joined(separator: ", "),
                        paths: found,
                        action: .deleteContents,
                        scope: .under(found.map(Posix.parent(of:))),
                        policy: policy,
                        caution: caution
                    )
                }
            }
        )
    }
}
