import AppKit
import CullCore
import SwiftUI

enum Theme {
    /// Terracotta. It marks the cut: the part of the disk about to be carved away, and the button that does it.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.94, green: 0.49, blue: 0.34, alpha: 1)
            : NSColor(srgbRed: 0.78, green: 0.33, blue: 0.20, alpha: 1)
    })

    static func color(for tier: Tier) -> Color {
        switch tier {
        case .safe: return .green
        case .rebuildable: return .orange
        case .review: return .blue
        }
    }

    static func color(for pressure: DiskSpace.Pressure) -> Color {
        switch pressure {
        case .comfortable: return .green
        case .tight: return .orange
        case .critical: return .red
        }
    }

    static let rowInset: CGFloat = 20
    static let cornerRadius: CGFloat = 10
}

extension DiskSpace.Pressure {
    var label: String? {
        switch self {
        case .comfortable: return nil
        case .tight: return "Getting tight"
        case .critical: return "Critical"
        }
    }
}
