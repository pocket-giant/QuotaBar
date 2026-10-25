import Testing
import Foundation

@Suite("AccountPersistence")
struct AccountPersistenceTests {

    /// A fresh, isolated defaults domain per test so nothing touches `.standard`.
    private func ephemeralDefaults() -> UserDefaults {
        let suite = "AccountPersistenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func snapshot(five: Int, seven: Int) -> UsageSnapshot {
        UsageSnapshot(fiveHourPercent: five, sevenDayPercent: seven,
                      fiveHourResetsAt: nil, sevenDayResetsAt: nil, fetchedAt: Date())
    }

    @Test("Snapshot round-trips for one account")
    func snapshotRoundTrips() {
        let defaults = ephemeralDefaults()
        let store = AccountPersistence(defaults: defaults, accountID: UUID())

        store.saveSnapshot(snapshot(five: 42, seven: 17))
        let loaded = store.loadSnapshot()

        #expect(loaded?.fiveHourPercent == 42)
        #expect(loaded?.sevenDayPercent == 17)
    }

    @Test("Snapshots are namespaced — one account's data is invisible to another")
    func snapshotNamespaced() {
        let defaults = ephemeralDefaults()
        let a = AccountPersistence(defaults: defaults, accountID: UUID())
        let b = AccountPersistence(defaults: defaults, accountID: UUID())

        a.saveSnapshot(snapshot(five: 90, seven: 90))

        #expect(a.loadSnapshot()?.fiveHourPercent == 90)
        #expect(b.loadSnapshot() == nil)
    }
}
