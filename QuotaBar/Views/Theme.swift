import SwiftUI

/// The popover's appearance choice: follow macOS, or force light or dark.
enum AppTheme: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The popover's own palette, one set per color scheme, so both themes are designed rather
/// than left to the system window material.
struct Palette {
    let background: Color
    let card: Color
    let cardBorder: Color
    let track: Color
    let text: Color
    let secondary: Color
    let tertiary: Color
    let accent: Color
    let shadow: Color

    static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .dark
            ? Palette(background: Color(hex: 0x0F_11_16), card: Color(hex: 0x1A_1D_25),
                      cardBorder: Color.white.opacity(0.07), track: Color.white.opacity(0.08),
                      text: Color(hex: 0xF2_F4_F8), secondary: Color(hex: 0x9A_A1_AF),
                      tertiary: Color(hex: 0x62_69_77), accent: Color(hex: 0x4C_A3_FF),
                      shadow: Color.black.opacity(0.35))
            : Palette(background: Color(hex: 0xF4_F5_F8), card: .white,
                      cardBorder: Color.black.opacity(0.06), track: Color.black.opacity(0.07),
                      text: Color(hex: 0x14_17_1F), secondary: Color(hex: 0x5E_65_73),
                      tertiary: Color(hex: 0x9A_A0_AC), accent: Color(hex: 0x0A_66_E0),
                      shadow: Color.black.opacity(0.06))
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.forScheme(.light)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Resolves the palette from the effective color scheme and publishes it to the subtree.
struct Themed: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.environment(\.palette, Palette.forScheme(scheme))
    }
}

/// A circular gauge: track, a rounded progress arc, and the percent in the middle.
struct UsageRing: View {
    let percent: Int
    let color: Color
    var lineWidth: CGFloat = 8
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle().stroke(palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: percent)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(percent)").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("%").font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .monospacedDigit().foregroundStyle(palette.text)
        }
    }
}
