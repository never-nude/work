import Foundation

/// Large things Cull reports and leaves alone, with the command that trims them properly.
enum Advisories {
    static let threshold: Int64 = 1_000_000_000

    static func detect(_ context: RuleContext, isCancelled: () -> Bool) -> [Advisory] {
        var found: [Advisory] = []

        if context.env.hasFullDiskAccess {
            let image = context.path("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
            if let stat = Posix.info(at: image), stat.kind == .file, stat.allocated >= threshold {
                found.append(Advisory(
                    id: "docker",
                    title: "Docker disk image",
                    detail: "Images, containers and volumes live inside one file that only Docker can shrink.",
                    bytes: stat.allocated,
                    hint: "docker system prune -a"
                ))
            }
        }

        if let models = context.directory(".ollama/models") {
            let size = DirectorySizer.measure(models, isCancelled: isCancelled).bytes
            if size >= threshold {
                found.append(Advisory(
                    id: "ollama",
                    title: "Ollama models",
                    detail: "Model weights you pulled. Remove the ones you no longer run.",
                    bytes: size,
                    hint: "ollama list"
                ))
            }
        }
        return found
    }
}

enum Catalog {
    /// Every rule, in the order categories appear within their tier.
    static let all: [Rule] = [
        // Safe
        .packageCaches,
        .appCaches,
        .chromiumCaches,
        .containerCaches,
        .xcodeCaches,
        .userLogs,
        .unavailableSimulators,
        .firmware,
        // Rebuildable
        .derivedData,
        .projectArtifacts,
        .deviceSupport,
        .previews,
        .toolDownloads,
        // Your call
        .trash,
        .oldDownloads,
        .simulatorRuntimes,
        .simulatorData,
        .deviceBackups,
        .archives,
    ]
}

/// What the catalog offers, for `cull --list` and the app's settings.
public enum CullCatalog {
    public struct Entry: Sendable, Codable, Identifiable {
        public let id: String
        public let title: String
        public let tier: Tier
        public let blurb: String
        public let symbol: String
    }

    public static var entries: [Entry] {
        Catalog.all.map { Entry(id: $0.id, title: $0.title, tier: $0.tier, blurb: $0.blurb, symbol: $0.symbol) }
    }
}
