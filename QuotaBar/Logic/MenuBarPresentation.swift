import Foundation

/// Pure computation of what the menu bar shows, across account counts. The N==1 branch
/// reproduces the single-account format exactly (percent + reset countdown), so existing
/// users see no change after the multi-account refactor. N≥2 uses the compact composed
/// form. Kept SwiftUI-free for testability; the view maps `worstPercent` to a color.
enum MenuBarPresentation {
    struct Result: Equatable {
        let text: String
        /// Highest percent across shown accounts, for the worst-case color. Nil when there's
        /// nothing to show.
        let worstPercent: Int?
    }

    /// - accounts: ordered accounts (label + optional shortCode).
    /// - snapshots: latest snapshot per account id (absent while loading).
    /// - mode: the (global) display-mode selection.
    static func compute(
        accounts: [Account],
        snapshots: [UUID: UsageSnapshot],
        mode: MenuBarDisplayMode,
        replaceExhausted: Bool = true,
        now: Date = Date()
    ) -> Result {
        guard !accounts.isEmpty else {
            return Result(text: "--%", worstPercent: nil)
        }

        // N==1: reproduce the single-account format exactly (percent + reset countdown).
        if accounts.count == 1 {
            let account = accounts[0]
            guard let snapshot = snapshots[account.id],
                  let active = MenuBarSelection.active(mode: mode, snapshot: snapshot, now: now) else {
                return Result(text: "--%", worstPercent: nil)
            }
            return Result(text: UsageFormatting.menuBarValue(active, replaceExhausted: replaceExhausted, now: now),
                          worstPercent: active.percent)
        }

        // N≥2: compact composed form with deduped, user-overridable prefixes.
        let prefixes = MultiAccountMenuBar.shortPrefixes(
            for: accounts.map(\.label),
            overrides: accounts.map(\.shortCode)
        )
        var percents: [Int] = []
        let segments = zip(prefixes, accounts).map { prefix, account -> String in
            if let snapshot = snapshots[account.id],
               let active = MenuBarSelection.active(mode: mode, snapshot: snapshot, now: now) {
                percents.append(active.percent)
                return "\(prefix) \(UsageFormatting.menuBarValue(active, replaceExhausted: replaceExhausted, now: now))"
            }
            return "\(prefix) --%"
        }
        return Result(text: segments.joined(separator: " · "), worstPercent: percents.max())
    }
}
