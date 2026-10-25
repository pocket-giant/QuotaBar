import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var viewModel: AccountsViewModel
    @State private var settingsExpanded = false

    /// Horizontal padding wrapping the matrix (matches `matrix`'s `.padding(.horizontal, 12)`).
    private static let matrixHPadding: CGFloat = 32

    private var accountCount: Int { viewModel.accounts.count }

    /// The matrix's grid width: label column + one column per account + hairline separators.
    private var matrixGridWidth: CGFloat {
        UsageMatrixView.labelWidth
            + UsageMatrixView.columnWidth * CGFloat(accountCount)
            + CGFloat(max(accountCount - 1, 0)) * UsageMatrixView.columnSpacing
    }

    /// Grid plus its surrounding padding — the width the matrix actually needs.
    private var matrixOuterWidth: CGFloat { matrixGridWidth + Self.matrixHPadding }

    /// The screen the popover opens on: `NSScreen.main` is the screen with the key window.
    /// The fallback only matters headless (no screens attached).
    private var visibleWidth: CGFloat { NSScreen.main?.visibleFrame.width ?? 1440 }

    /// Single account keeps the original 320-pt column; 2+ accounts widen to fit the matrix,
    /// up to what the screen can show.
    private var popoverWidth: CGFloat {
        PopoverLayout.width(accountCount: accountCount, matrixOuterWidth: matrixOuterWidth,
                            visibleWidth: visibleWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.accounts.isEmpty {
                emptyState
            } else {
                matrix
            }

            addAccountControls
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.primary.opacity(0.03))
        }
        .frame(width: popoverWidth)
        .task { await viewModel.requestNotificationAuthorization() }
    }

    @ViewBuilder
    private var matrix: some View {
        let content = UsageMatrixView(viewModel: viewModel, columns: viewModel.accountViews)
            .padding(.horizontal, 16).padding(.vertical, 14)
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
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.85), Color.blue],
                                         startPoint: .top, endPoint: .bottom)))
            Text("QuotaBar").font(.system(size: 17, weight: .semibold))
            Spacer()
            Button {
                Task { await viewModel.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Refresh all now")
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28)).foregroundStyle(.secondary)
            Text("No accounts yet").font(.system(size: 15, weight: .semibold))
            Text("Add an account below to start tracking its usage.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
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
        VStack(spacing: 4) {
            // Once an add-account login is running, its own controls replace the button that
            // started it — starting a second one would be refused anyway.
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
                    Label("Add account", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(Color.accentColor)
                .controlSize(.large)
            } else {
                LoginPill(viewModel: viewModel, accountID: nil)
            }

            if let error = viewModel.addAccountError {
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(3)
            } else {
                Text("Sign in with your browser, one account at a time.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("Menu bar").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                Picker("", selection: $viewModel.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            HStack {
                Text("Launch at login").font(.system(size: 13))
                Spacer()
                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { _ in viewModel.toggleLaunchAtLogin() }
                ))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }

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
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            DisclosureGroup(isExpanded: $settingsExpanded) {
                SettingsView(viewModel: viewModel)
            } label: {
                Label("Settings", systemImage: "gearshape").font(.system(size: 13))
            }

            HStack {
                // Credited fork: the original is MIT-licensed, by sam-pop.
                HStack(spacing: 0) {
                    Text("Fork of QuotaBar by sam-pop · ").foregroundStyle(.tertiary)
                    Link("Pocket Giant", destination: URL(string: "https://pocketgiant.games/")!)
                }
                .font(.system(size: 11))
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
