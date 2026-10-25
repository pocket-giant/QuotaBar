import SwiftUI

struct ProgressBarView: View {
    let percent: Int
    let color: Color
    /// The per-model lines inside a card's weekly block use a thinner bar.
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if percent > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.75), color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * clampedFraction, height))
                        .animation(.easeInOut(duration: 0.5), value: percent)
                }
            }
        }
        .frame(height: height)
    }

    private var clampedFraction: CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100.0
    }
}
