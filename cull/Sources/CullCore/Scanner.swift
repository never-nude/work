import Foundation

/// Finds what can be culled and weighs it. Read-only: scanning never changes anything on disk.
public final class Scanner: Sendable {
    public let environment: CullEnvironment
    public let options: ScanOptions
    let rules: [Rule]

    public convenience init(environment: CullEnvironment, options: ScanOptions = ScanOptions()) {
        self.init(environment: environment, options: options, rules: Catalog.all)
    }

    init(environment: CullEnvironment, options: ScanOptions, rules: [Rule]) {
        self.environment = environment
        self.options = options
        self.rules = rules
    }

    private struct Detected: Sendable {
        let ruleIndex: Int
        var candidates: [Candidate]
        var note: String?
    }

    private struct Job: Sendable {
        let ruleIndex: Int
        let candidate: Candidate
    }

    public func scan(progress: (@Sendable (ScanProgress) -> Void)? = nil) async -> ScanReport {
        let started = Date()
        let env = environment
        let options = options
        let guardian = SafetyGuard(home: env.home)
        let active = rules.filter { options.onlyCategories?.contains($0.id) ?? true }
        // Claims come from every rule, including ones filtered out of this scan, so a
        // catch-all rule never picks up something a specific rule owns.
        let claimed = Set(rules.flatMap(\.claims).map { $0.lowercased() })
        let context = RuleContext(env: env, options: options, claimed: claimed, memo: ScanMemo())
        var notes: [String] = []

        progress?(ScanProgress(phase: .detecting, completed: 0, total: active.count, current: "Looking around"))

        // 1. Detect: each rule lists what it found. Cheap, so every rule runs at once.
        let detected: [Detected] = await withTaskGroup(of: Detected.self) { group in
            for (index, rule) in active.enumerated() {
                group.addTask {
                    if rule.needsFullDiskAccess, !env.hasFullDiskAccess {
                        return Detected(ruleIndex: index, candidates: [], note: "Needs Full Disk Access")
                    }
                    if Task.isCancelled { return Detected(ruleIndex: index, candidates: []) }
                    return Detected(ruleIndex: index, candidates: rule.detect(context))
                }
            }
            var all: [Detected] = []
            for await result in group { all.append(result) }
            return all.sorted { $0.ruleIndex < $1.ruleIndex }
        }

        // 2. Vet: exclusions first, then the safety guard. A rule that proposes something
        //    the guard refuses has a bug, so say so instead of quietly dropping it.
        var jobs: [Job] = []
        var ruleNotes: [Int: String] = [:]
        for result in detected {
            let rule = active[result.ruleIndex]
            if let note = result.note { ruleNotes[result.ruleIndex] = note }
            var seenKeys = Set<String>()
            for var candidate in result.candidates {
                guard seenKeys.insert(candidate.key).inserted else { continue }
                let itemID = rule.id + "|" + candidate.key
                if options.exclusions.contains(itemID) { continue }

                if case .command(let arguments) = candidate.action {
                    if Self.isExcluded(candidate.measuredPaths ?? [], by: options.exclusions) { continue }
                    if let reason = guardian.refusal(forCommand: arguments) {
                        notes.append("Skipped \(candidate.title): \(reason)")
                        continue
                    }
                } else {
                    let hadPaths = !candidate.paths.isEmpty
                    let proposed = candidate
                    candidate.paths = proposed.paths.filter { path in
                        if Self.isExcluded([path], by: options.exclusions) { return false }
                        if let reason = guardian.refusal(for: path, action: proposed.action, scope: proposed.scope) {
                            notes.append("Skipped \(Format.tilde(path, home: env.home)): \(reason)")
                            return false
                        }
                        return true
                    }
                    if hadPaths, candidate.paths.isEmpty { continue }
                    if !hadPaths { continue }
                }
                jobs.append(Job(ruleIndex: result.ruleIndex, candidate: candidate))
            }
        }

        // 3. Weigh: the slow part. A handful of walkers at a time keeps the disk busy
        //    without starving everything else.
        let width = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
        var measurements = [Measurement?](repeating: nil, count: jobs.count)
        var completed = 0
        progress?(ScanProgress(phase: .measuring, completed: 0, total: jobs.count, current: ""))

        await withTaskGroup(of: (Int, Measurement).self) { group in
            var next = 0
            while next < min(width, jobs.count) {
                let index = next
                let job = jobs[index]
                next += 1
                group.addTask { (index, Self.measure(job.candidate)) }
            }
            while let (index, measurement) = await group.next() {
                measurements[index] = measurement
                completed += 1
                progress?(ScanProgress(
                    phase: .measuring, completed: completed, total: jobs.count, current: jobs[index].candidate.title
                ))
                if next < jobs.count, !Task.isCancelled {
                    let upcoming = next
                    let job = jobs[upcoming]
                    next += 1
                    group.addTask { (upcoming, Self.measure(job.candidate)) }
                }
            }
        }

        // 4. Decide what is pre-selected and assemble the report.
        var itemsByRule = [[CullItem]](repeating: [], count: active.count)
        for (index, job) in jobs.enumerated() {
            guard let measurement = measurements[index] else { continue }
            let rule = active[job.ruleIndex]
            let candidate = job.candidate
            guard measurement.bytes >= (candidate.minimumBytes ?? options.minimumItemBytes) else { continue }

            var lastUsed = candidate.lastUsed
            var selected: Bool
            switch candidate.policy {
            case .always:
                selected = true
            case .never:
                selected = false
            case .staleTree(let days):
                lastUsed = measurement.newest
                // If part of the tree could not be read, its freshness is unknown: leave it alone.
                selected = !measurement.incomplete && Self.isStale(measurement.newest, days: days, now: env.now)
            case .staleSince(let date, let days):
                selected = Self.isStale(date, days: days, now: env.now)
            case .staleProject(let date, let days):
                // Show whichever is more recent: work on the project, or something written into the item.
                if let inside = measurement.newest, date.map({ inside > $0 }) ?? true { lastUsed = inside }
                selected = !measurement.incomplete
                    && Self.isStale(date, days: days, now: env.now)
                    && Self.isStale(measurement.newest, days: days, now: env.now)
            }
            // The tier's promise outranks any rule: personal files are never pre-selected.
            if rule.tier == .review { selected = false }

            itemsByRule[job.ruleIndex].append(CullItem(
                id: rule.id + "|" + candidate.key,
                categoryID: rule.id,
                title: candidate.title,
                subtitle: candidate.subtitle,
                paths: candidate.paths,
                action: candidate.action,
                scope: candidate.scope,
                bytes: measurement.bytes,
                lastUsed: lastUsed,
                lastUsedLabel: candidate.lastUsedLabel,
                selectedByDefault: selected,
                caution: candidate.caution,
                incomplete: measurement.incomplete
            ))
        }

        var categories: [CullCategory] = []
        for (index, rule) in active.enumerated() {
            let items = itemsByRule[index].sorted { ($0.bytes, $1.title) > ($1.bytes, $0.title) }
            let note = ruleNotes[index]
            guard !items.isEmpty || note != nil else { continue }
            categories.append(CullCategory(
                id: rule.id, title: rule.title, blurb: rule.blurb, tier: rule.tier,
                symbol: rule.symbol, items: items, note: note
            ))
        }

        let cancelled = Task.isCancelled
        var advisories: [Advisory] = []
        if options.onlyCategories == nil, !cancelled {
            advisories = Advisories.detect(context, isCancelled: { Task.isCancelled })
        }
        if !env.hasFullDiskAccess {
            notes.insert(
                "Full Disk Access is off, so the Trash, device backups and sandboxed app caches were not scanned.",
                at: 0
            )
        }

        return ScanReport(
            categories: categories,
            advisories: advisories,
            notes: notes,
            disk: DiskSpace.of(path: env.home),
            startedAt: started,
            finishedAt: Date(),
            cancelled: cancelled,
            hasFullDiskAccess: env.hasFullDiskAccess
        )
    }

    /// The project folders this scan would search: the configured ones, or the usual places that exist.
    public func projectRoots() -> [String] {
        let context = RuleContext(env: environment, options: options, claimed: [], memo: ScanMemo())
        return ProjectScanner(context: context).roots()
    }

    private static func isExcluded(_ paths: [String], by exclusions: [String]) -> Bool {
        paths.contains { path in
            exclusions.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    private static func isStale(_ date: Date?, days: Int, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) >= Double(days) * 86_400
    }

    private static func measure(_ candidate: Candidate) -> Measurement {
        var total = Measurement()
        if let fixed = candidate.fixedBytes {
            total.bytes = fixed
            return total
        }
        for path in candidate.measuredPaths ?? candidate.paths {
            if Task.isCancelled {
                total.incomplete = true
                break
            }
            total.merge(DirectorySizer.measure(path, isCancelled: { Task.isCancelled }))
        }
        return total
    }
}
