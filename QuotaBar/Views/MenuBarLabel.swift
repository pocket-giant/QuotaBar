import SwiftUI
import AppKit

/// The menu-bar status item uses the same compact account segment for one or many visible
/// accounts: a colored dot and short account name followed by its current usage.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: AccountsViewModel

    var body: some View {
        if viewModel.menuBarAccounts.isEmpty {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .accessibilityLabel("Open QuotaBar")
                .help("Open QuotaBar")
        } else if viewModel.menuBarDisplayMode == .bars {
            // Stacked 5h/7d mini-bars per account (single or multi).
            Image(nsImage: MenuBarImage.twoStat(
                accounts: viewModel.menuBarAccounts,
                snapshots: viewModel.snapshots,
                now: viewModel.displayNow
            ))
        } else {
            Image(nsImage: MenuBarImage.multiAccount(
                accounts: viewModel.menuBarAccounts,
                snapshots: viewModel.snapshots,
                mode: viewModel.menuBarDisplayMode,
                replaceExhausted: viewModel.settings.replaceExhaustedWithCountdown,
                highSince: viewModel.highUsageSince,
                showNames: viewModel.settings.showAccountNames,
                now: viewModel.displayNow
            ))
        }
    }

}
