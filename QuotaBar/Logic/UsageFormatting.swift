import Foundation

/// Pure, nonisolated formatting helpers shared by the menu bar and popover. Extracted from
/// `UsageViewModel` (which is `@MainActor`) so nonisolated presentation code can use them.
enum UsageFormatting {

    /// Whole minutes rounded up, so an allowance still blocked for 20 seconds reads 1m.
    /// Never synthesizes a timestamp or displays a zero-length countdown.
    static func exhaustedCountdown(until date: Date?, now: Date = Date()) -> String? {
        guard let date, date > now else { return nil }
        let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    static func menuBarValue(_ active: MenuBarSelection.Active,
                             replaceExhausted: Bool = true, now: Date = Date()) -> String {
        if replaceExhausted, active.window == .fiveHour, active.percent >= 100,
           let countdown = exhaustedCountdown(until: active.resetsAt, now: now) {
            return countdown
        }
        return "\(active.percent)%"
    }

    /// True when the menu bar shows the exhausted 5-hour window as a reset countdown rather
    /// than a percent. Those countdowns are drawn blue; everything else keeps its level color.
    static func showsFiveHourCountdown(_ active: MenuBarSelection.Active,
                                       replaceExhausted: Bool = true, now: Date = Date()) -> Bool {
        replaceExhausted && active.window == .fiveHour && active.percent >= 100
            && exhaustedCountdown(until: active.resetsAt, now: now) != nil
    }

    /// Coarse countdown to a reset ("2d 3h" / "4h 12m" / "18m" / "now" / "—"). Matches the
    /// historical `UsageViewModel.resetCountdown` output exactly.
    static func resetCountdown(until date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 60 { return "now" }
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let days = hours / 24
        let remainingHours = hours % 24

        if days > 0 {
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// "just now" / "Ns ago" / "Nm ago" since a fetch time.
    static func lastUpdatedText(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }

    /// Fine-grained live countdown ("1h 2m" / "3m 4s" / "5s" / "now" / "—").
    static func liveCountdown(until date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let total = max(0, Int(date.timeIntervalSince(now)))
        if total == 0 { return "now" }
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
