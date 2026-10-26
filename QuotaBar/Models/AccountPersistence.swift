import Foundation

/// Per-account persistence of the last snapshot, namespaced by account
/// id so two accounts never collide on the old flat `"lastSnapshot"` key. `UserDefaults` is injected so tests use an ephemeral suite instead of the shared
/// `.standard` domain.
struct AccountPersistence {
    let defaults: UserDefaults
    let accountID: UUID

    private var snapshotKey: String { "lastSnapshot-\(accountID.uuidString)" }
    private var allowanceKey: String { "allowanceMonitor-\(accountID.uuidString)" }

    func loadAllowanceState() -> AllowanceMonitor.State {
        guard let data = defaults.data(forKey: allowanceKey),
              let state = try? JSONDecoder().decode(AllowanceMonitor.State.self, from: data) else {
            return AllowanceMonitor.State()
        }
        return state
    }

    func saveAllowanceState(_ state: AllowanceMonitor.State) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: allowanceKey) }
    }

    init(defaults: UserDefaults = .standard, accountID: UUID) {
        self.defaults = defaults
        self.accountID = accountID
    }

    func loadCardState() -> AccountCardState {
        guard let data = defaults.data(forKey: "accountCard-\(accountID.uuidString)"),
              let state = try? JSONDecoder().decode(AccountCardState.self, from: data) else {
            return AccountCardState()
        }
        return state
    }

    func saveCardState(_ state: AccountCardState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: "accountCard-\(accountID.uuidString)")
        }
    }

    func saveSnapshot(_ snapshot: UsageSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    func loadSnapshot() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
