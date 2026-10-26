import SwiftUI
import AppKit

/// The menu-bar status item. For a single account it reproduces the historical rendering
/// exactly (5h/7d badge + percent + reset countdown, color via the badge). For two or more
/// accounts it draws a compact composed image — a colored dot per account plus the
/// `P 45% · W 82%` text — since `Text`/SF Symbols render monochrome in a `MenuBarExtra`.
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
        } else if viewModel.menuBarAccounts.count == 1 {
            singleAccountLabel
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

    // MARK: - Single account (unchanged rendering)

    @ViewBuilder
    private var singleAccountLabel: some View {
        let account = viewModel.menuBarAccounts[0]
        let snapshot = viewModel.snapshots[account.id]
        let active = MenuBarSelection.active(mode: viewModel.menuBarDisplayMode, snapshot: snapshot,
                                             now: viewModel.displayNow)
        let needsRefresh = viewModel.needsReAuth[account.id] ?? false
        let countdown = active.map {
            UsageFormatting.showsFiveHourCountdown($0, replaceExhausted: viewModel.settings.replaceExhaustedWithCountdown,
                                                   highSince: viewModel.highUsageSince[account.id],
                                                   now: viewModel.displayNow)
        } ?? false

        HStack(spacing: 4) {
            if needsRefresh {
                Image(systemName: "key.slash.fill").foregroundStyle(.red)
                Text("Refresh")
            } else {
                Image(nsImage: MenuBarImage.badge(
                    window: active?.window ?? (viewModel.menuBarDisplayMode == .auto ? .fiveHour : viewModel.menuBarDisplayMode),
                    isAuto: viewModel.menuBarDisplayMode == .auto,
                    percent: active?.percent ?? 0,
                    countdown: countdown
                ))
                if countdown {
                    Image(nsImage: MenuBarImage.coloredText(viewModel.menuBarText, color: MenuBarImage.countdownColor))
                } else {
                    Text(viewModel.menuBarText).monospacedDigit()
                }
            }
        }
    }
}
