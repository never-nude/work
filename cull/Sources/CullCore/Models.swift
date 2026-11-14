import Foundation

/// How much it costs you to lose something.
public enum Tier: String, Codable, Sendable, CaseIterable, Comparable {
    /// Regenerates on its own, nobody notices. Selected by default.
    case safe
    /// Costs a rebuild or a re-download next time. Selected by default only when stale.
    case rebuildable
    /// Personal files. Never selected by default, and files go to the Trash rather than being deleted.
    case review

    private var order: Int {
        switch self {
        case .safe: return 0
        case .rebuildable: return 1
        case .review: return 2
        }
    }

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.order < rhs.order }

    public var title: String {
        switch self {
        case .safe: return "Safe to cull"
        case .rebuildable: return "Rebuildable"
        case .review: return "Your call"
        }
    }

    public var explanation: String {
        switch self {
        case .safe: return "Regenerates on its own"
        case .rebuildable: return "Costs a rebuild or re-download; stale ones are pre-selected"
        case .review: return "Never pre-selected; files go to the Trash"
        }
    }
}

/// What culling an item actually does.
public enum ItemAction: Sendable, Hashable, Codable {
    /// Permanently remove each path.
    case delete
    /// Permanently remove everything inside each path, keeping the directory itself.
    case deleteContents
    /// Move each path to the Trash.
    case trash
    /// Run a vetted command (only `xcrun simctl …` forms pass the safety guard).
    case command([String])

    public var isReversible: Bool {
        if case .trash = self { return true }
        return false
    }
}

/// The region a rule promises to stay inside. The safety guard holds every path to it.
public enum PathScope: Sendable, Hashable, Codable {
    /// The path must be strictly inside one of these absolute directories.
    case under([String])
    /// The path must be strictly inside `root` and its last component must be one of `names`.
    case artifact(root: String, names: [String])
}

public struct CullItem: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let categoryID: String
    public var title: String
    public var subtitle: String?
    /// Absolute paths this item covers. Empty for command-backed items.
    public var paths: [String]
    public var action: ItemAction
    public var scope: PathScope?
    public var bytes: Int64
    /// When this was last built, modified, or added, depending on the rule.
    public var lastUsed: Date?
    /// Verb that goes with `lastUsed`, e.g. "Last built".
    public var lastUsedLabel: String?
    public var selectedByDefault: Bool
    /// A reason to think twice, e.g. "Slack is running".
    public var caution: String?
    /// True when some of the item could not be read, so `bytes` is a lower bound.
    public var incomplete: Bool

    public init(
        id: String, categoryID: String, title: String, subtitle: String? = nil, paths: [String],
        action: ItemAction, scope: PathScope?, bytes: Int64, lastUsed: Date? = nil,
        lastUsedLabel: String? = nil, selectedByDefault: Bool, caution: String? = nil,
        incomplete: Bool = false
    ) {
        self.id = id
        self.categoryID = categoryID
        self.title = title
        self.subtitle = subtitle
        self.paths = paths
        self.action = action
        self.scope = scope
        self.bytes = bytes
        self.lastUsed = lastUsed
        self.lastUsedLabel = lastUsedLabel
        self.selectedByDefault = selectedByDefault
        self.caution = caution
        self.incomplete = incomplete
    }
}

public struct CullCategory: Identifiable, Sendable, Codable {
    public let id: String
    public var title: String
    public var blurb: String
    public var tier: Tier
    /// SF Symbol name for the app; ignored by the CLI.
    public var symbol: String
    public var items: [CullItem]
    /// Why the category is empty or partial, e.g. "Needs Full Disk Access".
    public var note: String?

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var defaultBytes: Int64 { items.reduce(0) { $0 + ($1.selectedByDefault ? $1.bytes : 0) } }

    public init(id: String, title: String, blurb: String, tier: Tier, symbol: String, items: [CullItem], note: String? = nil) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.tier = tier
        self.symbol = symbol
        self.items = items
        self.note = note
    }
}

/// Something large that Cull reports but deliberately will not touch.
public struct Advisory: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public var title: String
    public var detail: String
    public var bytes: Int64
    /// A command the user can run themselves.
    public var hint: String?

    public init(id: String, title: String, detail: String, bytes: Int64, hint: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.bytes = bytes
        self.hint = hint
    }
}

public struct ScanReport: Sendable, Codable {
    public var categories: [CullCategory]
    public var advisories: [Advisory]
    public var notes: [String]
    public var disk: DiskSpace?
    public var startedAt: Date
    public var finishedAt: Date
    public var cancelled: Bool
    public var hasFullDiskAccess: Bool

    public init(
        categories: [CullCategory] = [], advisories: [Advisory] = [], notes: [String] = [],
        disk: DiskSpace? = nil, startedAt: Date = Date(), finishedAt: Date = Date(),
        cancelled: Bool = false, hasFullDiskAccess: Bool = true
    ) {
        self.categories = categories
        self.advisories = advisories
        self.notes = notes
        self.disk = disk
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.cancelled = cancelled
        self.hasFullDiskAccess = hasFullDiskAccess
    }

    public var allItems: [CullItem] { categories.flatMap(\.items) }
    public var totalBytes: Int64 { categories.reduce(0) { $0 + $1.totalBytes } }
    public var defaultBytes: Int64 { categories.reduce(0) { $0 + $1.defaultBytes } }
    public var defaultSelection: Set<String> { Set(allItems.filter(\.selectedByDefault).map(\.id)) }

    public func categories(in tier: Tier) -> [CullCategory] {
        categories.filter { $0.tier == tier }
    }

    public func bytes(selected: Set<String>) -> Int64 {
        allItems.reduce(0) { $0 + (selected.contains($1.id) ? $1.bytes : 0) }
    }
}

public struct ScanOptions: Sendable, Codable, Equatable {
    /// Xcode build data untouched for this long is pre-selected.
    public var staleDays: Int
    /// Project dependencies and build folders are pre-selected once the project has been idle this long.
    public var projectStaleDays: Int
    /// Downloads older than this are listed for review.
    public var downloadsAgeDays: Int
    /// Folders to search for stale project artifacts. `nil` means auto-detect the usual suspects.
    public var projectRoots: [String]?
    /// Things that must never be offered: absolute paths (which also cover everything inside them) or item IDs.
    public var exclusions: [String]
    /// Restrict the scan to these category IDs.
    public var onlyCategories: Set<String>?
    /// Items smaller than this are not worth listing.
    public var minimumItemBytes: Int64
    /// A simulator has to hold at least this much to be offered for erasing (a never-booted one is ~20 MB).
    public var livedInSimulatorBytes: Int64

    public init(
        staleDays: Int = 14, projectStaleDays: Int = 30, downloadsAgeDays: Int = 90,
        projectRoots: [String]? = nil, exclusions: [String] = [],
        onlyCategories: Set<String>? = nil, minimumItemBytes: Int64 = 1_000_000,
        livedInSimulatorBytes: Int64 = 200_000_000
    ) {
        self.staleDays = staleDays
        self.projectStaleDays = projectStaleDays
        self.downloadsAgeDays = downloadsAgeDays
        self.projectRoots = projectRoots
        self.exclusions = exclusions
        self.onlyCategories = onlyCategories
        self.minimumItemBytes = minimumItemBytes
        self.livedInSimulatorBytes = livedInSimulatorBytes
    }
}

public struct ScanProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case detecting, measuring }
    public var phase: Phase
    public var completed: Int
    public var total: Int
    public var current: String

    public var fraction: Double {
        guard phase == .measuring, total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}
