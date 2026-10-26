import AppKit
import SwiftUI
import Testing

@Suite("Account card rendered layout")
@MainActor
struct CardRenderingTests {
    @Test("Collapsed cards render shorter while preserving account identity")
    func layout() throws {
        let suite = "CardRendering-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let account = Account(label: "Claude Work", accountUUID: "fixture", email: "work@example.com")
        let second = Account(label: "Codex", accountUUID: "fixture2", email: "personal@example.com", provider: .openai)
        let store = AccountsStore(defaults: defaults)
        store.save([account, second])
        let exhausted = UsageSnapshot(fiveHourPercent: 0, sevenDayPercent: 100,
            fiveHourResetsAt: nil, sevenDayResetsAt: now.addingTimeInterval(200_000), fetchedAt: now)
        let available = UsageSnapshot(fiveHourPercent: 30, sevenDayPercent: 40,
            fiveHourResetsAt: now.addingTimeInterval(3_600), sevenDayResetsAt: now.addingTimeInterval(300_000), fetchedAt: now)
        AccountPersistence(defaults: defaults, accountID: account.id).saveSnapshot(exhausted)
        AccountPersistence(defaults: defaults, accountID: second.id).saveSnapshot(available)
        let deps = AccountsViewModel.Dependencies(adapters: .init(anthropic: .unavailable(.anthropic), openai: .unavailable(.openai)),
            openURL: { _ in }, now: Date.init, resolveLegacyCredentials: { nil }, deleteLegacyArtifacts: {},
            requestNotificationAuthorization: { nil }, addNotification: { _ in })
        let vm = AccountsViewModel(accountsStore: store, credentialStore: InMemoryAccountCredentialStore(),
                                   defaults: defaults, startTimer: false, deps: deps)
        func render(_ name: String, columns: [AccountsViewModel.AccountView]) throws -> CGFloat {
            let view = UsageMatrixView(viewModel: vm, columns: columns)
                .padding(16).frame(width: columns.count == 1 ? 320 : 600)
                .background(Palette.forScheme(.dark).background)
                .environment(\.palette, Palette.forScheme(.dark)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            let image = try #require(renderer.nsImage)
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            if ProcessInfo.processInfo.environment["QUOTABAR_RENDER_CARDS"] == "1" {
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/quotabar-\(name).png"))
            }
            return image.size.height
        }
        #expect(vm.menuBarAccounts.map(\.id) == [account.id, second.id])
        let expanded = try render("expanded", columns: Array(vm.accountViews.prefix(1)))
        vm.setCardCollapsed(account.id, true)
        let collapsed = try render("collapsed", columns: Array(vm.accountViews.prefix(1)))
        #expect(collapsed < expanded)
        #expect(vm.menuBarAccounts.map(\.id) == [second.id])
        #expect(vm.menuBarText == "30%")
        _ = try render("mixed", columns: vm.accountViews)
        #expect(vm.accounts.first?.email == "work@example.com")
        #expect(vm.cardStates[second.id]?.isCollapsed == false)
        vm.setCardCollapsed(second.id, true)
        #expect(vm.menuBarAccounts.isEmpty)
        #expect(vm.accountViews.count == 2)
        // With all accounts hidden the status item retains its app icon for reopening.
        #expect(ImageRenderer(content: MenuBarLabel(viewModel: vm)).nsImage != nil)
        vm.setCardCollapsed(account.id, false)
        #expect(vm.menuBarAccounts.map(\.id) == [account.id])
    }
}
