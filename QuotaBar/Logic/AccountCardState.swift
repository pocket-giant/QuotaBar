import Foundation

/// UI preferences only; usage and credentials remain in their existing stores.
struct AccountCardState: Codable, Equatable {
    var isCollapsed = false
    var suggestionDismissed = false
    var exhaustedSince: Date?

    static func isExhausted(_ snapshot: UsageSnapshot) -> Bool {
        (snapshot.fiveHourPercent ?? 0) >= 100 || snapshot.sevenDayPercent >= 100
    }

    /// All exhausted windows must reset before the account can be used again.
    static func resetAt(_ snapshot: UsageSnapshot) -> Date? {
        var resets: [Date] = []
        if (snapshot.fiveHourPercent ?? 0) >= 100 {
            guard let reset = snapshot.fiveHourResetsAt else { return nil }
            resets.append(reset)
        }
        if snapshot.sevenDayPercent >= 100 {
            guard let reset = snapshot.sevenDayResetsAt else { return nil }
            resets.append(reset)
        }
        return resets.max()
    }

    mutating func record(_ snapshot: UsageSnapshot) {
        if Self.isExhausted(snapshot) {
            if exhaustedSince == nil { exhaustedSince = snapshot.fetchedAt }
        } else {
            // Only a fresh successful response establishes restored allowance.
            if exhaustedSince != nil { isCollapsed = false }
            exhaustedSince = nil
            suggestionDismissed = false
        }
    }

    func suggestsCollapse(snapshot: UsageSnapshot?, now: Date) -> Bool {
        guard !isCollapsed, !suggestionDismissed, let snapshot,
              Self.isExhausted(snapshot) else { return false }
        let longWait = Self.resetAt(snapshot).map { $0.timeIntervalSince(now) > 86_400 } ?? false
        let longExhaustion = exhaustedSince.map { now.timeIntervalSince($0) > 86_400 } ?? false
        return longWait || longExhaustion
    }
}
