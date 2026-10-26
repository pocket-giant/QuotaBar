import SwiftUI

/// SwiftUI level color for a usage percent (green < 70 ≤ orange < 90 ≤ red). Shared by the
/// popover sections and the single-account menu bar; mirrors `MenuBarImage.levelColor`.
enum UsageColor {
    static func level(_ percent: Int) -> Color {
        switch percent {
        case ..<70: return .green
        case ..<90: return .orange
        default:    return .red
        }
    }
}
