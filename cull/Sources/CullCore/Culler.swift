import Foundation

public struct CullOutcome: Sendable, Identifiable, Codable, Equatable {
    public enum Status: String, Sendable, Codable {
        /// Permanently deleted.
        case removed
        /// Moved to the Trash; the space comes back when the Trash is emptied.
        case trashed
        /// Some of it went, some of it would not.
        case partial
        /// Already gone by the time Cull got to it.
        case skipped
        case failed
    }

    public let id: String
    public let title: String
    public let status: Status
    /// Estimated bytes deleted or moved to the Trash.
    public let bytes: Int64
    public let message: String?
}

public struct CullSummary: Sendable, Codable {
    public var outcomes: [CullOutcome]
    public var diskBefore: DiskSpace?
    public var diskAfter: DiskSpace?
    public var cancelled: Bool

    public var deletedBytes: Int64 {
        outcomes.reduce(0) { $0 + (($1.status == .removed || $1.status == .partial) ? $1.bytes : 0) }
    }

    public var trashedBytes: Int64 {
        outcomes.reduce(0) { $0 + ($1.status == .trashed ? $1.bytes : 0) }
    }

    public var problems: [CullOutcome] {
        outcomes.filter { $0.status == .failed || $0.status == .partial }
    }

    public var succeededCount: Int {
        outcomes.filter { $0.status == .removed || $0.status == .trashed || $0.status == .partial }.count
    }
}

public struct CullProgress: Sendable, Equatable {
    public var completed: Int
    public var total: Int
    public var current: String
    public var bytesSoFar: Int64

    public init(completed: Int, total: Int, current: String, bytesSoFar: Int64) {
        self.completed = completed
        self.total = total
        self.current = current
        self.bytesSoFar = bytesSoFar
    }

    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

/// Carries out a cull. Every path is re-checked against the safety guard and the
/// filesystem at the moment of deletion; nothing from the scan is taken on trust.
public final class Culler: Sendable {
    public let environment: CullEnvironment
    private let guardian: SafetyGuard

    public init(environment: CullEnvironment) {
        self.environment = environment
        self.guardian = SafetyGuard(home: environment.home)
    }

    public func cull(
        _ items: [CullItem], progress: (@Sendable (CullProgress) -> Void)? = nil
    ) async -> CullSummary {
        let before = DiskSpace.of(path: environment.home)
        var outcomes: [CullOutcome] = []
        var bytesSoFar: Int64 = 0
        var cancelled = false

        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                cancelled = true
                break
            }
            progress?(CullProgress(completed: index, total: items.count, current: item.title, bytesSoFar: bytesSoFar))
            let outcome = perform(item)
            if outcome.status != .failed, outcome.status != .skipped { bytesSoFar += outcome.bytes }
            outcomes.append(outcome)
        }
        progress?(CullProgress(completed: outcomes.count, total: items.count, current: "", bytesSoFar: bytesSoFar))

        return CullSummary(
            outcomes: outcomes, diskBefore: before, diskAfter: DiskSpace.of(path: environment.home),
            cancelled: cancelled
        )
    }

    // MARK: One item

    private func outcome(_ item: CullItem, _ status: CullOutcome.Status, bytes: Int64 = 0, _ message: String? = nil) -> CullOutcome {
        CullOutcome(id: item.id, title: item.title, status: status, bytes: bytes, message: message)
    }

    func perform(_ item: CullItem) -> CullOutcome {
        // Deleting as root would sail past the permissions that keep mistakes small.
        // No exception for sandbox homes: `sudo` plus a mistyped CULL_HOME is exactly the mistake.
        if Posix.isRoot {
            return outcome(item, .failed, "Cull refuses to delete anything as root. Run it as yourself, without sudo.")
        }

        if case .command(let arguments) = item.action {
            return run(arguments, for: item)
        }

        guard !item.paths.isEmpty else { return outcome(item, .failed, "Nothing to remove") }

        var done = 0
        var removedAnything = false
        var problems: [String] = []
        for path in item.paths {
            switch remove(path, action: item.action, scope: item.scope) {
            case .done:
                done += 1
                removedAnything = true
            case .absent:
                break
            case .problem(let message, let removedSome):
                problems.append(message)
                removedAnything = removedAnything || removedSome
            }
        }

        let finished: CullOutcome.Status = item.action == .trash ? .trashed : .removed
        if problems.isEmpty {
            return done == 0 ? outcome(item, .skipped, "Already gone") : outcome(item, finished, bytes: item.bytes)
        }

        let summary = problems.count == 1 ? problems[0] : "\(problems[0]) (and \(problems.count - 1) more)"
        guard removedAnything else { return outcome(item, .failed, summary) }
        // Some of it went. Weigh what is left so the report stays honest.
        var remaining: Int64 = 0
        for path in item.paths { remaining += DirectorySizer.measure(path).bytes }
        return outcome(item, .partial, bytes: max(0, item.bytes - remaining), summary)
    }

    private func run(_ arguments: [String], for item: CullItem) -> CullOutcome {
        if let reason = guardian.refusal(forCommand: arguments) {
            return outcome(item, .failed, "Refused: \(reason)")
        }
        guard let runner = environment.runner else {
            return outcome(item, .failed, "Running commands is not available here")
        }
        guard let result = runner.run(arguments, timeout: 600, captureErrors: true) else {
            return outcome(item, .failed, "Could not launch \(arguments[0])")
        }
        if result.succeeded { return outcome(item, .removed, bytes: item.bytes) }
        if result.timedOut { return outcome(item, .failed, "Timed out") }
        let lastLine = result.output.split(whereSeparator: \.isNewline).last.map(String.init)
        return outcome(item, .failed, lastLine ?? "Exited with status \(result.status)")
    }

    // MARK: One path

    private enum PathResult {
        case done
        case absent
        /// `removedSome` is true when part of the path went before the problem.
        case problem(String, removedSome: Bool)

        static func refused(_ message: String) -> PathResult { .problem(message, removedSome: false) }
    }

    private func remove(_ path: String, action: ItemAction, scope: PathScope?) -> PathResult {
        let shown = Format.tilde(path, home: environment.home)
        if let reason = guardian.refusal(for: path, action: action, scope: scope) {
            return .refused("Refused \(shown): \(reason)")
        }
        guard let stat = Posix.info(at: path) else { return .absent }

        // The item has to be exactly where its path says. If any folder on the way is a
        // symlink, the path is a description of somewhere else, and Cull will not follow it.
        let parent = Posix.parent(of: path)
        guard let realParent = Posix.realPath(parent), realParent == parent else {
            return .refused("Refused \(shown): it is reached through a symlink")
        }

        // A build artifact is only believed while the manifest that explains it still sits beside it.
        if case .artifact = scope {
            guard stat.kind == .directory, Self.artifactIsVouchedFor(path) else {
                return .refused("Refused \(shown): nothing beside it says it is a build artifact")
            }
        }

        do {
            switch action {
            case .delete:
                try Self.removeTree(path)
            case .deleteContents:
                guard stat.kind == .directory else {
                    return .refused("Refused \(shown): it is no longer a folder")
                }
                guard let names = Posix.entries(of: path) else {
                    return .refused("Could not read \(shown)")
                }
                var failures = 0
                var firstError: String?
                for name in names {
                    do {
                        try Self.removeTree(Posix.join(path, name))
                    } catch {
                        failures += 1
                        if firstError == nil { firstError = error.localizedDescription }
                    }
                }
                if failures > 0 {
                    let what = Format.count(failures, "item")
                    return .problem(
                        "\(what) in \(shown) could not be removed: \(firstError ?? "unknown error")",
                        removedSome: failures < names.count
                    )
                }
            case .trash:
                guard let trash = environment.trash else {
                    return .refused("Moving to the Trash is not available here")
                }
                try trash(path)
            case .command:
                return .refused("Not a file action")
            }
        } catch {
            return .problem("\(shown): \(error.localizedDescription)", removedSome: false)
        }
        return .done
    }

    /// The scanner only proposes `node_modules` next to a `package.json`, `.build` next to a
    /// `Package.swift`, and so on. This asks the same question again, independently, at deletion time.
    static func artifactIsVouchedFor(_ path: String) -> Bool {
        let project = Posix.parent(of: path)
        func beside(_ name: String) -> Bool { Posix.info(at: Posix.join(project, name)) != nil }
        switch Posix.lastComponent(of: path) {
        case "node_modules", ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular":
            return beside("package.json")
        case ".build":
            return beside("Package.swift")
        case "Pods":
            return beside("Podfile")
        case "target":
            return beside("Cargo.toml")
        case ".venv", "venv":
            return Posix.info(at: Posix.join(path, "pyvenv.cfg")) != nil
        case "DerivedData":
            return beside("Package.swift") || (Posix.entries(of: project) ?? []).contains {
                $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace")
            }
        default:
            return false
        }
    }

    /// Removes a file, a symlink (the link, never its target), or a whole tree.
    static func removeTree(_ path: String) throws {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            // Read-only trees refuse the first attempt. Unlock the directories and retry once.
            guard Posix.info(at: path)?.kind == .directory else { throw error }
            Posix.makeTreeWritable(path)
            try FileManager.default.removeItem(atPath: path)
        }
    }
}
