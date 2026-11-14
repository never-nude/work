import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct DiskSpace: Sendable, Codable, Equatable {
    public var total: Int64
    /// Free right now.
    public var free: Int64
    /// Space macOS says it can reclaim by itself when asked (snapshots, purgeable caches).
    public var purgeable: Int64

    public init(total: Int64, free: Int64, purgeable: Int64 = 0) {
        self.total = total
        self.free = free
        self.purgeable = purgeable
    }

    /// What Finder calls "available": free plus purgeable.
    public var available: Int64 { free + purgeable }
    public var used: Int64 { max(0, total - available) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    public var availableFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }

    public enum Pressure: String, Sendable, Codable { case comfortable, tight, critical }

    public var pressure: Pressure {
        let gigabyte: Int64 = 1_000_000_000
        if available < 5 * gigabyte || availableFraction < 0.03 { return .critical }
        if available < 20 * gigabyte || availableFraction < 0.10 { return .tight }
        return .comfortable
    }

    /// The name of the volume holding `path`, e.g. "Macintosh HD".
    public static func volumeName(of path: String) -> String? {
        #if os(macOS)
        return (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeNameKey]))?.volumeName
        #else
        return nil
        #endif
    }

    /// Capacity of the volume holding `path`.
    public static func of(path: String) -> DiskSpace? {
        #if os(macOS)
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]
        if let values = try? url.resourceValues(forKeys: keys),
           let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity {
            let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(free)
            return DiskSpace(total: Int64(total), free: Int64(free), purgeable: max(0, important - Int64(free)))
        }
        #endif
        var info = statvfs()
        guard statvfs(path, &info) == 0 else { return nil }
        let blockSize = Int64(info.f_frsize)
        return DiskSpace(total: Int64(info.f_blocks) * blockSize, free: Int64(info.f_bavail) * blockSize)
    }
}
