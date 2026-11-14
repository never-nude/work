import Foundation

public enum CullInfo {
    public static let version = "0.1.0"
}

public enum Format {
    /// Decimal units, the way Finder counts: 1 GB is 1,000,000,000 bytes.
    public static func bytes(_ value: Int64) -> String {
        let magnitude = Double(abs(value))
        let sign = value < 0 ? "-" : ""
        if magnitude < 1_000 { return "\(sign)\(Int(magnitude)) bytes" }
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        for (scale, unit) in units where magnitude >= scale {
            let scaled = magnitude / scale
            // One decimal below 100, none above: 9.4 GB, 38.2 GB, 512 MB.
            if scaled >= 99.95 || unit == "KB" {
                return "\(sign)\(Int(scaled.rounded())) \(unit)"
            }
            return "\(sign)\(String(format: "%.1f", scaled)) \(unit)"
        }
        return "\(sign)\(Int(magnitude)) bytes"
    }

    /// "today", "yesterday", "5 days ago", "3 months ago", "2 years ago".
    public static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 { return "just now" }
        let days = Int(seconds / 86_400)
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        case 60..<730: return "\(days / 30) months ago"
        default: return "\(days / 365) years ago"
        }
    }

    /// Replaces the home prefix with "~".
    public static func tilde(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// "Last built 4 months ago", or `nil` when the item carries no date.
    public static func lastUsed(_ item: CullItem, now: Date = Date()) -> String? {
        guard let date = item.lastUsed else { return nil }
        return "\(item.lastUsedLabel ?? "Last used") \(age(of: date, now: now))"
    }

    /// One line on where the disk stands: "12.3 GB available of 494 GB".
    public static func disk(_ disk: DiskSpace) -> String {
        "\(bytes(disk.available)) available of \(bytes(disk.total))"
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    public static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(plural ?? singular + "s")"
    }
}
