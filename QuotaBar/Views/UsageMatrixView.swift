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
    static let columnSpacing: CGFloat = 10

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
        VStack(alignment: .leading, spacing: 16) {
            header(column, index: index, now: now)
            if let snap = column.snapshot {
                if let five = snap.fiveHourEffectivePercent(now: now) {
                    usageBlock("5-hour session", percent: five, resetsAt: snap.fiveHourResetsAt,
                               leader: fiveHourLeader, live: true, now: now)
                }
                usageBlock("Weekly", percent: snap.sevenDayEffectivePercent(now: now),
                           resetsAt: snap.sevenDayResetsAt, leader: weeklyLeader, live: false, now: now)
                if let limits = snap.modelLimits, !limits.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(limits) { modelLine($0, now: now) }
                    }
                }
            } else if case .error(let message) = column.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.orange).lineLimit(4)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(16)
        .frame(minWidth: Self.columnWidth, maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .popover(isPresented: editBinding(for: column.account.id), arrowEdge: .bottom) { editForm(column.account) }
    }

    // MARK: - Header

    private func header(_ column: AccountsViewModel.AccountView, index: Int, now: Date) -> some View {
        let account = column.account
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(AccountColor.color(forIndex: index)).frame(width: 9, height: 9)
                Text(account.label).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    draftLabel = account.label
                    draftShortCode = account.shortCode ?? ""
                    editingID = account.id
                } label: { Image(systemName: "pencil").font(.system(size: 12)) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Rename / set menu-bar code")
                Button(role: .destructive) {
                    Task { await viewModel.remove(account.id) }
                } label: { Image(systemName: "trash").font(.system(size: 12)) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove this account")
            }
            if let email = account.email, email != account.label {
                Text(email).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if mixedProviders {
                HStack(spacing: 4) {
                    // The same asset the menu bar draws. Claude's mark in its brand orange;
                    // OpenAI's is black/white so it takes the secondary style.
                    if let mark = ProviderShape.mark(for: account.provider, mixed: true).image {
                        Image(nsImage: mark)
                            .renderingMode(.template)
                            .resizable().scaledToFit().frame(height: 11)
                            .foregroundStyle(account.provider == .anthropic
                                             ? AnyShapeStyle(Color(nsColor: ProviderShape.claudeBrand))
                                             : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    }
                    Text(account.provider.displayName).font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            freshness(column, now: now)
            loginExpiryLine(column, now: now)
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
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .labelStyle(DotLabelStyle())
            }
        } else if case .error = column.state {
            Text("Couldn't load").font(.system(size: 11)).foregroundStyle(.orange)
        } else {
            Text("Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
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

    private func usageBlock(_ title: String, percent: Int, resetsAt: Date?, leader: Bool, live: Bool, now: Date) -> some View {
        let color: Color = UsageColor.level(percent)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(.system(size: 11, weight: .semibold))
                    .tracking(0.6).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if leader {
                    Text("Highest").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                }
            }
            .frame(height: 20)
            Text("\(percent)%")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(color)
            ProgressBarView(percent: percent, color: color)
            Label {
                Text("Resets in \(live ? UsageFormatting.liveCountdown(until: resetsAt, now: now) : UsageFormatting.resetCountdown(until: resetsAt, now: now))")
                    .font(.system(size: 12)).monospacedDigit()
            } icon: {
                Image(systemName: "clock").font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        }
    }

    /// One per-model weekly limit, under the weekly numbers. A limit the provider flags as
    /// critical shows red while it still has usage.
    private func modelLine(_ limit: ModelLimit, now: Date) -> some View {
        let shown = UsageSnapshot.effectivePercent(limit.percent, resetsAt: limit.resetsAt, now: now)
        let color: Color = (limit.severity == "critical" && shown > 0) ? .red : UsageColor.level(shown)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(limit.modelName).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(shown)%").font(.system(size: 12, weight: .semibold))
                    .monospacedDigit().foregroundStyle(color)
            }
            ProgressBarView(percent: shown, color: color, height: 5)
            Text("Resets in \(UsageFormatting.resetCountdown(until: limit.resetsAt, now: now))")
                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
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
