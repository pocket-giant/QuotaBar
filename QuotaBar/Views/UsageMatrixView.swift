import SwiftUI

/// The account cards: one card per account, side by side, each holding that account's 5-hour
/// and weekly usage. A single account fills the popover; two or more sit in a row and the
/// highest account in each window is flagged "Highest".
struct UsageMatrixView: View {
    @ObservedObject var viewModel: AccountsViewModel
    let columns: [AccountsViewModel.AccountView]

    /// No label column any more: every card carries its own labels.
    static let labelWidth: CGFloat = 0
    static let columnWidth: CGFloat = 236
    static let columnSpacing: CGFloat = 12

    @Environment(\.palette) private var palette
    @State private var editingID: UUID?
    @State private var draftLabel = ""
    @State private var draftShortCode = ""

    private struct CellData {
        let percent: Int
        let resetsAt: Date?
    }

    /// Same rule as the menu bar: name the provider only when there is more than one.
    private var mixedProviders: Bool {
        MultiAccountMenuBar.providerShapes(for: columns.map(\.account.provider))
    }

    var body: some View {
        // One tick keeps every window's effective percent (and the leader flags) rolling over
        // the instant a reset passes.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let fiveHour = leaderFlags(now: now) { snap in snap.fiveHourEffectivePercent(now: now) }
            let weekly = leaderFlags(now: now) { snap in snap.sevenDayEffectivePercent(now: now) }
            HStack(alignment: .top, spacing: Self.columnSpacing) {
                // Keyed by account id, not position: reordering moves a card's view identity
                // with its account, so the edit popover follows the account.
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    card(column, index: index, now: now,
                         fiveHourLeader: fiveHour[index], weeklyLeader: weekly[index])
                }
            }
        }
    }

    private func leaderFlags(now: Date, _ value: (UsageSnapshot) -> Int?) -> [Bool] {
        UsageComparison.leaders(columns.map { $0.snapshot.flatMap(value) })
    }

    // MARK: - Card

    private func card(_ column: AccountsViewModel.AccountView, index: Int, now: Date,
                      fiveHourLeader: Bool, weeklyLeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header(column, index: index)
            if let snap = column.snapshot {
                HStack(alignment: .top, spacing: 12) {
                    if let five = snap.fiveHourEffectivePercent(now: now) {
                        gauge("5-hour", percent: five, resetsAt: snap.fiveHourResetsAt,
                              leader: fiveHourLeader, fiveHour: true, now: now)
                    }
                    gauge("Weekly", percent: snap.sevenDayEffectivePercent(now: now),
                          resetsAt: snap.sevenDayResetsAt, leader: weeklyLeader, fiveHour: false, now: now)
                }
                .frame(maxWidth: .infinity)
                if let limits = snap.modelLimits, !limits.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(limits) { modelLine($0, now: now) }
                    }
                }
            } else if case .error(let message) = column.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.orange).lineLimit(4)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 110)
            }
            VStack(alignment: .leading, spacing: 6) {
                freshness(column, now: now)
                loginExpiryLine(column, now: now)
            }
        }
        .padding(16)
        .frame(minWidth: Self.columnWidth, maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card)
            .shadow(color: palette.shadow, radius: 10, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.cardBorder, lineWidth: 1))
        .popover(isPresented: editBinding(for: column.account.id), arrowEdge: .bottom) { editForm(column.account) }
    }

    // MARK: - Header

    private func header(_ column: AccountsViewModel.AccountView, index: Int) -> some View {
        let account = column.account
        let tint = AccountColor.color(forIndex: index)
        return HStack(spacing: 10) {
            Text(String(account.label.prefix(1)).uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(account.label).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text).lineLimit(1)
                    if mixedProviders, let mark = ProviderShape.mark(for: account.provider, mixed: true).image {
                        // The same asset the menu bar draws. Claude's mark in its brand orange;
                        // OpenAI's is black/white so it takes the secondary color.
                        Image(nsImage: mark)
                            .renderingMode(.template)
                            .resizable().scaledToFit().frame(height: 11)
                            .foregroundStyle(account.provider == .anthropic
                                             ? Color(nsColor: ProviderShape.claudeBrand) : palette.secondary)
                            .help(account.provider.displayName)
                    }
                }
                if let email = account.email, email != account.label {
                    Text(email).font(.system(size: 11)).foregroundStyle(palette.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button("Rename…") {
                    draftLabel = account.label
                    draftShortCode = account.shortCode ?? ""
                    editingID = account.id
                }
                Divider()
                Button("Remove account", role: .destructive) {
                    Task { await viewModel.remove(account.id) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Rename, set menu-bar code, or remove")
        }
    }

    @ViewBuilder
    private func freshness(_ column: AccountsViewModel.AccountView, now: Date) -> some View {
        // A login that needs starting, or one already running, replaces the freshness line:
        // how stale the numbers are matters less than the fact that they've stopped updating.
        if viewModel.loginAffordance(for: column.account.id) != .none {
            LoginPill(viewModel: viewModel, accountID: column.account.id, layout: .compact)
        } else if let snapshot = column.snapshot {
            let stale = now.timeIntervalSince(snapshot.fetchedAt) > 300
            let ago = UsageFormatting.lastUpdatedText(since: snapshot.fetchedAt, now: now)
            if stale {
                Button {
                    Task { await viewModel.refresh(column.account.id) }
                } label: {
                    pill(text: "Stale · \(ago)", systemImage: "arrow.clockwise", tint: .orange)
                }
                .buttonStyle(.plain).help("Refresh this account now")
            } else {
                Label("Updated \(ago)", systemImage: "circle.fill")
                    .font(.system(size: 11)).foregroundStyle(palette.tertiary)
                    .labelStyle(DotLabelStyle())
            }
        } else if case .error = column.state {
            Text("Couldn't load").font(.system(size: 11)).foregroundStyle(.orange)
        } else {
            Text("Loading…").font(.system(size: 11)).foregroundStyle(palette.tertiary)
        }
    }

    /// Gated on `loginAffordance == .none`, so this never shows alongside the dead-login pill.
    @ViewBuilder
    private func loginExpiryLine(_ column: AccountsViewModel.AccountView, now: Date) -> some View {
        if viewModel.loginAffordance(for: column.account.id) == .none,
           let warning = LoginExpiry.warning(refreshTokenExpiresAt: column.refreshTokenExpiresAt, now: now) {
            Button {
                Task { await viewModel.beginLogin(column.account.id) }
            } label: {
                pill(text: warning, systemImage: "clock.badge.exclamationmark", tint: .orange)
            }
            .buttonStyle(.plain).help(loginHelp(for: column.account.id))
        }
    }

    /// Provider-aware like `LoginPill`'s own help: this line starts the same login.
    private func loginHelp(for accountID: UUID) -> String {
        switch viewModel.loginProvider(for: accountID) {
        case .anthropic: return "Opens claude.ai in your browser to sign in"
        case .openai: return "Opens auth.openai.com in your browser to sign in"
        }
    }

    // MARK: - Usage

    private func gauge(_ title: String, percent: Int, resetsAt: Date?, leader: Bool,
                       fiveHour: Bool, now: Date) -> some View {
        VStack(spacing: 8) {
            UsageRing(percent: percent, color: UsageColor.level(percent))
                .frame(width: 84, height: 84)
                .overlay(alignment: .topTrailing) {
                    if leader {
                        Circle().fill(Color.orange).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(palette.card, lineWidth: 2))
                            .help("Highest of your accounts")
                    }
                }
                .padding(.bottom, 2)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.text)
            // Only the 5-hour countdown is blue; the weekly one stays neutral.
            Text(fiveHour ? UsageFormatting.liveCountdown(until: resetsAt, now: now)
                          : UsageFormatting.resetCountdown(until: resetsAt, now: now))
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(fiveHour ? palette.accent : palette.secondary)
                .help("Time until this window resets")
        }
        .frame(maxWidth: .infinity)
    }

    /// One per-model weekly limit, under the weekly numbers. A limit the provider flags as
    /// critical shows red while it still has usage.
    private func modelLine(_ limit: ModelLimit, now: Date) -> some View {
        let shown = UsageSnapshot.effectivePercent(limit.percent, resetsAt: limit.resetsAt, now: now)
        let color: Color = (limit.severity == "critical" && shown > 0) ? .red : UsageColor.level(shown)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(limit.modelName).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(shown)%").font(.system(size: 12, weight: .semibold))
                    .monospacedDigit().foregroundStyle(color)
            }
            ProgressBarView(percent: shown, color: color, height: 5)
            Text("Resets in \(UsageFormatting.resetCountdown(until: limit.resetsAt, now: now))")
                .font(.system(size: 11)).foregroundStyle(palette.tertiary).lineLimit(1)
        }
    }

    // MARK: - Editing

    private func editBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { editingID == id }, set: { if !$0 { editingID = nil } })
    }

    private func editForm(_ account: Account) -> some View {
        VStack(spacing: 8) {
            TextField("Label", text: $draftLabel).textFieldStyle(.roundedBorder)
            TextField("Menu-bar code", text: $draftShortCode).textFieldStyle(.roundedBorder)
                .help("Menu-bar prefix (e.g. P, W, 🏠). Blank = auto from the label.")
            // The popover is bound to `editingID`, which a move doesn't touch, so it stays
            // open and several moves in a row work without reopening it.
            HStack {
                Button {
                    viewModel.moveAccount(account.id, by: -1)
                } label: { Label("Move left", systemImage: "arrow.left") }
                    .disabled(viewModel.accounts.first?.id == account.id)
                Button {
                    viewModel.moveAccount(account.id, by: 1)
                } label: { Label("Move right", systemImage: "arrow.right") }
                    .disabled(viewModel.accounts.last?.id == account.id)
                Spacer()
            }
            .controlSize(.small)
            HStack {
                Spacer()
                Button("Cancel") { editingID = nil }
                Button("Save") {
                    let trimmed = draftLabel.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { viewModel.relabel(account.id, to: trimmed) }
                    viewModel.setShortCode(account.id, to: draftShortCode)
                    editingID = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12).frame(width: 240)
    }

    // MARK: - Bits

    private func pill(text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.5))
    }
}

/// A tiny leading status dot for the "Updated Ns ago" line.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(.green)
            configuration.title
        }
    }
}
