import Foundation
import Testing

@Suite("Account card preferences")
struct AccountCardStateTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func snapshot(_ five: Int = 100, weekly: Int = 0, reset: TimeInterval? = 100_000) -> UsageSnapshot {
        UsageSnapshot(fiveHourPercent: five, sevenDayPercent: weekly,
                      fiveHourResetsAt: reset.map { now.addingTimeInterval($0) },
                      sevenDayResetsAt: now.addingTimeInterval(200_000), fetchedAt: now)
    }

    @Test("Long exhaustion suggests collapse without applying it; dismissal survives relaunch")
    func suggestionAndPersistence() throws {
        var state = AccountCardState()
        state.record(snapshot())
        #expect(!state.isCollapsed)
        #expect(state.suggestsCollapse(snapshot: snapshot(), now: now))
        state.suggestionDismissed = true
        let suite = "CardTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = AccountPersistence(defaults: defaults, accountID: UUID())
        state.isCollapsed = true
        persistence.saveCardState(state)
        #expect(persistence.loadCardState() == state)
        state.isCollapsed = false
        #expect(!state.suggestsCollapse(snapshot: snapshot(), now: now))
    }

    @Test("Only confirmed availability expands an exhausted card; resets alone do not")
    func restoredAllowance() {
        var state = AccountCardState(isCollapsed: true)
        state.record(snapshot())
        state.record(snapshot(100, reset: -10))
        #expect(state.isCollapsed)
        state.record(snapshot(0, weekly: 100))
        #expect(state.isCollapsed)
        state.record(snapshot(0))
        #expect(!state.isCollapsed)
        #expect(state.exhaustedSince == nil)
        #expect(!state.suggestionDismissed)
    }

    @Test("Short waits do not suggest; an unknown reset still suggests after 24 hours")
    func suggestionTiming() {
        var state = AccountCardState()
        state.record(snapshot(reset: nil))
        #expect(!state.suggestsCollapse(snapshot: snapshot(reset: 100), now: now))
        #expect(!state.suggestsCollapse(snapshot: snapshot(reset: nil), now: now.addingTimeInterval(86_400)))
        #expect(state.suggestsCollapse(snapshot: snapshot(reset: nil), now: now.addingTimeInterval(86_401)))
        #expect(!state.suggestsCollapse(snapshot: nil, now: now.addingTimeInterval(90_000)))
    }

    @Test("Reset countdown waits for every blocking window and does not invent unknown resets")
    func blockingWindows() {
        #expect(AccountCardState.resetAt(snapshot(100, weekly: 100)) == now.addingTimeInterval(200_000))
        #expect(AccountCardState.resetAt(snapshot(reset: nil)) == nil)
        #expect(AccountCardState.resetAt(snapshot(0)) == nil)
    }

    @Test("Collapsing an available account persists until a later exhausted-to-available transition")
    func availableCollapse() {
        var state = AccountCardState(isCollapsed: true)
        state.record(snapshot(20))
        #expect(state.isCollapsed)
    }
}
