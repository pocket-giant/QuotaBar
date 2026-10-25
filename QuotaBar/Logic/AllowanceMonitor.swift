import Foundation

/// Consumes successful, fresh provider responses only. A local clock tick never enters
/// this monitor. State is bounded to two windows and persisted independently per account.
struct AllowanceMonitor {
    enum Window: String, Codable { case fiveHour, weekly }
    enum Event: Equatable {
        case restored(Window)
        case warning(Window, threshold: Int, percent: Int)
    }
    struct Sample: Codable {
        var percent: Int
        var resetsAt: Date?
        var fired: Set<Int>
        var restoredReset: Date?
    }
    struct State: Codable {
        var fiveHour: Sample?
        var weekly: Sample?
        var fetchedAt: Date?
    }

    private(set) var state: State
    // First live response in a process establishes a silent baseline, even with a cache.
    private var hasLiveBaseline = false

    init(state: State = State()) { self.state = state }

    mutating func record(_ snapshot: UsageSnapshot, thresholds: [Int]) -> [Event] {
        guard state.fetchedAt.map({ snapshot.fetchedAt > $0 }) ?? true else { return [] }
        let silent = !hasLiveBaseline
        hasLiveBaseline = true
        var events: [Event] = []
        func sample(_ percent: Int?, reset: Date?, old: Sample?, window: Window) -> Sample? {
            guard let percent else { return old } // Missing data proves no transition.
            var fired = old?.fired ?? []
            // A reset timestamp must have passed and the response must show availability.
            // With no timestamp, a fresh exhausted → available transition is the evidence.
            let resetPassed = old?.resetsAt.map { snapshot.fetchedAt >= $0 } ?? true
            let advanced = old?.resetsAt.flatMap { previous in reset.map { $0 > previous } } ?? false
            let dropped = old.map { percent < $0.percent } ?? false
            let newCycle = resetPassed && (advanced || (dropped && percent < (thresholds.min() ?? 80)))
            if newCycle { fired = [] }
            var restoredReset = old?.restoredReset
            let alreadyRestored = old?.resetsAt != nil && old?.resetsAt == restoredReset
            if !silent, let old, old.percent >= 100, percent < 100, resetPassed, !alreadyRestored {
                events.append(.restored(window))
                restoredReset = old.resetsAt
            }
            for threshold in thresholds where percent >= threshold {
                if !silent, let old, old.percent < threshold, !fired.contains(threshold) {
                    events.append(.warning(window, threshold: threshold, percent: percent))
                }
                fired.insert(threshold)
            }
            return Sample(percent: percent, resetsAt: reset, fired: fired, restoredReset: restoredReset)
        }
        state.fiveHour = sample(snapshot.fiveHourPercent, reset: snapshot.fiveHourResetsAt,
                                old: state.fiveHour, window: .fiveHour)
        state.weekly = sample(snapshot.sevenDayPercent, reset: snapshot.sevenDayResetsAt,
                              old: state.weekly, window: .weekly)
        state.fetchedAt = snapshot.fetchedAt
        return events
    }
}
