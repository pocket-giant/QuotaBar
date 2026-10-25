import SwiftUI
import AppKit

/// Severity colors for usage levels. Tuned per appearance so the percentage text stays
/// legible on both the light and dark popover (system yellow washes out on light).
enum UsageColor {
    static func level(_ percent: Int) -> Color {
        switch percent {
        case ..<50: return Color(nsColor: dynamic(light: 0x1E_9E_4A, dark: 0x34_D0_58))
        case ..<75: return Color(nsColor: dynamic(light: 0xC9_8A_00, dark: 0xF5_C5_42))
        default:    return Color(nsColor: dynamic(light: 0xD9_2D_3A, dark: 0xFF_5A_5F))
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}
