import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var viewModel: AccountsViewModel

    var body: some View {
        PopoverContent(viewModel: viewModel)
            .modifier(Themed())
            .preferredColorScheme(viewModel.settings.theme.colorScheme)
            .onAppear { viewModel.settings.theme.apply() }
            .onChange(of: viewModel.settings.theme) { $0.apply() }
            .task { await viewModel.requestNotificationAuthorization() }
    }
}

/// Split from `UsagePopoverView` so the palette is read *inside* the forced color scheme.
private struct PopoverContent: View {
    @ObservedObject var viewModel: AccountsViewModel
    @Environment(\.palette) private var palette
    @State private var settingsExpanded = false

    /// Horizontal padding wrapping the cards (16 pt each side).
    private static let matrixHPadding: CGFloat = 32

    private var accountCount: Int { viewModel.accounts.count }

    /// The cards' width: one column per account plus the gaps between them.
    private var matrixGridWidth: CGFloat {
        UsageMatrixView.labelWidth
            + UsageMatrixView.columnWidth * CGFloat(accountCount)
            + CGFloat(max(accountCount - 1, 0)) * UsageMatrixView.columnSpacing
    }

    /// Grid plus its surrounding padding: the width the cards actually need.
    private var matrixOuterWidth: CGFloat { matrixGridWidth + Self.matrixHPadding }

    /// The screen the popover opens on. The fallback only matters headless.
    private var visibleWidth: CGFloat { NSScreen.main?.visibleFrame.width ?? 1440 }

    /// Single account keeps the 320-pt column; 2+ accounts widen to fit the cards, up to what
    /// the screen can show.
    private var popoverWidth: CGFloat {
        PopoverLayout.width(accountCount: accountCount, matrixOuterWidth: matrixOuterWidth,
                            visibleWidth: visibleWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.accounts.isEmpty {
                emptyState
            } else {
                matrix
            }
            addAccountControls
            footer
        }
        .frame(width: popoverWidth)
        .background(palette.background)
    }

    @ViewBuilder
    private var matrix: some View {
        let content = UsageMatrixView(viewModel: viewModel, columns: viewModel.accountViews)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
        if PopoverLayout.scrolls(matrixOuterWidth: matrixOuterWidth, visibleWidth: visibleWidth) {
            ScrollView(.horizontal, showsIndicators: true) { content }
        } else {
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x4C_A3_FF), Color(hex: 0x0A_66_E0)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 1) {
                Text("QuotaBar").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
            Spacer()
            Button {
                Task { await viewModel.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(palette.card))
                    .overlay(Circle().stroke(palette.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain).help("Refresh all now")
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
    }

    private var subtitle: String {
        switch accountCount {
        case 0: return "Usage limits at a glance"
        case 1: return "1 account"
        default: return "\(accountCount) accounts"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28)).foregroundStyle(palette.secondary)
            Text("No accounts yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text)
            Text("Add an account below to start tracking its usage.")
                .font(.system(size: 12)).foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 16)
    }

    /// A provider's own logo for a menu item. Sizing and tint both live in the `NSImage`
    /// (see `ProviderShape.menuImage`) because SwiftUI's `NSMenuItem` bridge drops `.frame`
    /// and `.foregroundStyle` on a non-SF image.
    @ViewBuilder
    private func providerMark(_ shape: ProviderShape) -> some View {
        if let image = shape.menuImage(pointSize: 14) { Image(nsImage: image) }
    }

    private var addAccountControls: some View {
        VStack(spacing: 6) {
            // Once an add-account login is running, its own controls replace the button that
            // started it: starting a second one would be refused anyway.
            if viewModel.loginAffordance(for: nil) == .none {
                Menu {
                    Button {
                        Task { await viewModel.beginAddAccountLogin(provider: .anthropic) }
                    } label: { Label { Text("Claude") } icon: { providerMark(.claudeMark) } }
                        .help("Opens claude.ai in your browser to sign in")
                    Button {
                        Task { await viewModel.beginAddAccountLogin(provider: .openai) }
                    } label: { Label { Text("OpenAI / Codex") } icon: { providerMark(.openAIMark) } }
                        .help("Opens auth.openai.com in your browser to sign in with your ChatGPT account")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("Add account").font(.system(size: 13, weight: .medium))
                    }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .tint(palette.accent)
                // The borderless menu drops styling on its label, so the frame lives outside it.
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            } else {
                LoginPill(viewModel: viewModel, accountID: nil)
            }

            if let error = viewModel.addAccountError {
                Text(error).font(.system(size: 11)).foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center).lineLimit(3)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                row("Menu bar") {
                    Picker("Menu bar", selection: $viewModel.menuBarDisplayMode) {
                        ForEach([MenuBarDisplayMode.fiveHour, .sevenDay], id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                separator
                row("Theme") {
                    Picker("Theme", selection: $viewModel.settings.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                separator
                row("Account names in menu bar") {
                    Toggle("Account names in menu bar", isOn: $viewModel.settings.showAccountNames)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                separator
                row("Launch at login") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { _ in viewModel.toggleLaunchAtLogin() }
                    ))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                separator
                DisclosureGroup(isExpanded: $settingsExpanded) {
                    SettingsView(viewModel: viewModel).padding(.bottom, 6)
                } label: {
                    Text("More settings").font(.system(size: 13)).foregroundStyle(palette.text)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.cardBorder, lineWidth: 1))

            if viewModel.notificationsAuthorized == false {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.slash")
                        Text("Notifications off. Enable in System Settings").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
                }
                .buttonStyle(.borderless).padding(.top, 10)
            }

            HStack {
                // Credited fork: the original is MIT-licensed, by sam-pop.
                HStack(spacing: 0) {
                    Text("Fork of QuotaBar by sam-pop · ").foregroundStyle(palette.tertiary)
                    Link("Pocket Giant", destination: URL(string: "https://pocketgiant.games/")!)
                        .foregroundStyle(palette.accent)
                }
                .font(.system(size: 11))
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.bottom, 14)
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(palette.text).fixedSize()
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
    }

    private var separator: some View {
        Rectangle().fill(palette.cardBorder).frame(height: 1).padding(.leading, 12)
    }
}
