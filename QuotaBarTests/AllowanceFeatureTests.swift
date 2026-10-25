import Foundation
import Testing

@Suite("Session menu-bar behavior")
struct SessionMenuBarTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private func snapshot(_ five: Int?, reset: Date?) -> UsageSnapshot {
        UsageSnapshot(fiveHourPercent: five, sevenDayPercent: 99, fiveHourResetsAt: reset,
                      sevenDayResetsAt: nil, fetchedAt: now)
    }

    @Test("Exhausted 5-hour usage stays selected in Auto and fixed 5h")
    func exhaustedSelection() throws {
        for mode in [MenuBarDisplayMode.auto, .fiveHour] {
            let active = try #require(MenuBarSelection.active(mode: mode,
                snapshot: snapshot(100, reset: now.addingTimeInterval(600)), now: now))
            #expect(active.window == .fiveHour)
            #expect(UsageFormatting.menuBarValue(active, now: now) == "10m")
        }
    }

    @Test("Countdowns round up and never invent a reset")
    func formatting() {
        for (seconds, expected) in [(1.0, "1m"), (60, "1m"), (1_140, "19m"), (4_260, "1h 11m"), (7_201, "2h 1m")] {
            #expect(UsageFormatting.exhaustedCountdown(until: now.addingTimeInterval(seconds), now: now) == expected)
        }
        #expect(UsageFormatting.exhaustedCountdown(until: nil, now: now) == nil)
        #expect(UsageFormatting.exhaustedCountdown(until: now, now: now) == nil)
        let active = MenuBarSelection.Active(window: .fiveHour, percent: 100, resetsAt: nil)
        #expect(UsageFormatting.menuBarValue(active, now: now) == "100%")
    }

    @Test("Multiple accounts count down independently, advance locally, and return to percentages")
    func independentCountdowns() {
        let a = Account(label: "Claude", shortCode: "Claude")
        let b = Account(label: "Codex", shortCode: "Codex", provider: .openai)
        let snapshots = [a.id: snapshot(100, reset: now.addingTimeInterval(1_140)),
                         b.id: snapshot(100, reset: now.addingTimeInterval(4_260))]
        func text(_ time: Date, countdown: Bool = true) -> String {
            MenuBarPresentation.compute(accounts: [a, b], snapshots: snapshots, mode: .auto,
                                        replaceExhausted: countdown, now: time).text
        }
        #expect(text(now) == "Claude 19m · Codex 1h 11m")
        #expect(text(now.addingTimeInterval(60)) == "Claude 18m · Codex 1h 10m")
        #expect(text(now.addingTimeInterval(1_140)) == "Claude 0% · Codex 52m")
        #expect(text(now, countdown: false) == "Claude 100% · Codex 100%")
    }

    @Test("Weekly remains manually selectable and is never presented as a session countdown")
    func manualWeekly() {
        let a = Account(label: "Work")
        let result = MenuBarPresentation.compute(accounts: [a], snapshots: [a.id: snapshot(100, reset: nil)],
                                                mode: .sevenDay, now: now)
        #expect(result.text == "99%")
    }
}

@Suite("Fresh allowance detection and deduplication")
struct AllowanceMonitorTests {
    private func snap(_ five: Int? = 100, seven: Int = 100, at: Double,
                      reset: Double? = 100, weeklyReset: Double? = 200) -> UsageSnapshot {
        UsageSnapshot(fiveHourPercent: five, sevenDayPercent: seven,
                      fiveHourResetsAt: reset.map(Date.init(timeIntervalSince1970:)),
                      sevenDayResetsAt: weeklyReset.map(Date.init(timeIntervalSince1970:)),
                      fetchedAt: Date(timeIntervalSince1970: at))
    }

    @Test("Launch at high usage is silent, including a persisted exhausted cache")
    func launchBaseline() {
        var first = AllowanceMonitor()
        #expect(first.record(snap(at: 10), thresholds: [80, 95]).isEmpty)
        var relaunched = AllowanceMonitor(state: first.state)
        #expect(relaunched.record(snap(0, seven: 0, at: 201, reset: 500, weeklyReset: 800), thresholds: [80, 95]).isEmpty)
    }

    @Test("A clock passing reset is insufficient; fresh availability restores each window once")
    func restoresIndependently() {
        var monitor = AllowanceMonitor()
        _ = monitor.record(snap(at: 10), thresholds: [80, 95])
        // Provider still reports exhausted after the timestamp. No invented restoration.
        #expect(monitor.record(snap(at: 101), thresholds: [80, 95]).isEmpty)
        #expect(monitor.record(snap(2, at: 102, reset: 500), thresholds: [80, 95]) == [.restored(.fiveHour)])
        #expect(monitor.record(snap(2, at: 103, reset: 500), thresholds: [80, 95]).isEmpty)
        #expect(monitor.record(snap(2, seven: 1, at: 201, reset: 500, weeklyReset: 800), thresholds: [80, 95]) == [.restored(.weekly)])
    }

    @Test("Early percentage corrections and missing windows are not reset evidence")
    func noFalseReset() {
        var monitor = AllowanceMonitor()
        _ = monitor.record(snap(at: 10), thresholds: [80, 95])
        #expect(monitor.record(snap(nil, at: 101), thresholds: [80, 95]).isEmpty)
        #expect(monitor.record(snap(90, at: 50), thresholds: [80, 95]).isEmpty) // out of order
        var early = AllowanceMonitor()
        _ = early.record(snap(at: 10), thresholds: [80, 95])
        #expect(early.record(snap(90, seven: 90, at: 20), thresholds: [80, 95]).isEmpty)
    }

    @Test("Warnings fire once per threshold, not per poll or boundary fluctuation")
    func deduplicatesWarnings() {
        var monitor = AllowanceMonitor()
        _ = monitor.record(snap(70, seven: 0, at: 1), thresholds: [80, 95])
        #expect(monitor.record(snap(80, seven: 0, at: 2), thresholds: [80, 95]) == [.warning(.fiveHour, threshold: 80, percent: 80)])
        #expect(monitor.record(snap(79, seven: 0, at: 3), thresholds: [80, 95]).isEmpty)
        #expect(monitor.record(snap(80, seven: 0, at: 4), thresholds: [80, 95]).isEmpty)
        #expect(monitor.record(snap(96, seven: 0, at: 5), thresholds: [80, 95]) == [.warning(.fiveHour, threshold: 95, percent: 96)])
        #expect(monitor.record(snap(96, seven: 0, at: 6), thresholds: [80, 95]).isEmpty)
    }

    @Test("Repeated stale-reset payloads cannot duplicate a restoration")
    func staleResetDeduplication() {
        var monitor = AllowanceMonitor()
        _ = monitor.record(snap(at: 1), thresholds: [80, 95])
        #expect(monitor.record(snap(0, at: 101), thresholds: [80, 95]) == [.restored(.fiveHour)])
        _ = monitor.record(snap(at: 102), thresholds: [80, 95])
        #expect(monitor.record(snap(0, at: 103), thresholds: [80, 95]).isEmpty)
    }

    @Test("Per-account state persists and a later usage cycle re-arms warnings")
    func persistenceAndNextCycle() throws {
        let suite = "AllowanceFeatures-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = AccountPersistence(defaults: defaults, accountID: UUID())
        let b = AccountPersistence(defaults: defaults, accountID: UUID())
        var monitor = AllowanceMonitor()
        _ = monitor.record(snap(0, seven: 0, at: 1), thresholds: [80, 95])
        _ = monitor.record(snap(90, seven: 0, at: 2), thresholds: [80, 95])
        a.saveAllowanceState(monitor.state)
        #expect(a.loadAllowanceState().fiveHour?.fired == [80])
        #expect(b.loadAllowanceState().fiveHour == nil)
        var relaunched = AllowanceMonitor(state: a.loadAllowanceState())
        #expect(relaunched.record(snap(79, seven: 0, at: 3), thresholds: [80, 95]).isEmpty)
        #expect(relaunched.record(snap(80, seven: 0, at: 4), thresholds: [80, 95]).isEmpty)
        _ = relaunched.record(snap(0, seven: 0, at: 101, reset: 500), thresholds: [80, 95])
        #expect(relaunched.record(snap(80, seven: 0, at: 102, reset: 500), thresholds: [80, 95]) == [.warning(.fiveHour, threshold: 80, percent: 80)])
    }
}

@Suite("QuotaBar settings persistence")
struct AppSettingsTests {
    @Test("Defaults are enabled, thresholds are 80/95, and explicit display choices survive")
    func settingsRoundTrip() {
        let suite = "QuotaBarSettings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = AppSettings.load(from: defaults)
        #expect(initial == AppSettings())
        #expect(initial.initialDisplayMode(from: defaults) == .fiveHour)
        var settings = initial
        settings.showFiveHourByDefault = false
        settings.replaceExhaustedWithCountdown = false
        settings.notifyFiveHourReset = false
        settings.notifyWeeklyReset = false
        settings.usageWarnings = false
        settings.warningThresholds = [70, 98]
        settings.save(to: defaults)
        let reloaded = AppSettings.load(from: UserDefaults(suiteName: suite)!)
        #expect(reloaded == settings)
        #expect(reloaded.initialDisplayMode(from: defaults) == .sevenDay)
        defaults.set("auto", forKey: "menuBarDisplayMode")
        #expect(reloaded.initialDisplayMode(from: defaults) == .auto)
        defaults.set("7d", forKey: "menuBarDisplayMode")
        #expect(AppSettings().initialDisplayMode(from: defaults) == .sevenDay)
    }
}

@Suite("Runtime reset recovery")
@MainActor
struct AllowanceRuntimeTests {
    @Test("API failures keep the baseline; recovery after sleep emits one fresh reset")
    func failureAndRecovery() async throws {
        struct Offline: Error {}
        let suite = "AllowanceRuntime-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let store = InMemoryAccountCredentialStore([
            id: CachedCredentials(accessToken: "t", refreshToken: "r", expiresAt: nil)])
        var time = Date(timeIntervalSince1970: 10)
        var failed = false
        var percent = 100.0
        var events: [AllowanceMonitor.Event] = []
        let runtime = AccountRuntime(id: id, credentials: AccountCredentialManager(store: store),
            persistence: AccountPersistence(defaults: defaults, accountID: id),
            deps: .init(fetchUsage: { _ in
                if failed { throw Offline() }
                return UsageResponse(fiveHour: UsagePeriod(utilization: percent, resetsAt: "1970-01-01T00:01:40Z"),
                                     sevenDay: UsagePeriod(utilization: 0, resetsAt: ""))
            }, refreshToken: { $0 }, now: { time }, onAllowanceEvent: { events.append($0) }))
        await runtime.refresh()
        #expect(events.isEmpty)
        time = Date(timeIntervalSince1970: 200)
        failed = true
        await runtime.refresh()
        #expect(events.isEmpty)
        #expect(runtime.snapshot?.fiveHourPercent == 100)
        time = Date(timeIntervalSince1970: 201)
        failed = false
        percent = 0
        await runtime.refresh()
        #expect(events == [.restored(.fiveHour)])
        time = Date(timeIntervalSince1970: 202)
        await runtime.refresh()
        #expect(events == [.restored(.fiveHour)])
    }
}
