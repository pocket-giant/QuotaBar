import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AccountsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show 5-hour usage by default", isOn: Binding(
                get: { viewModel.settings.showFiveHourByDefault },
                set: { viewModel.setFiveHourDefault($0) }))
            Toggle("Replace 100% with countdown", isOn: $viewModel.settings.replaceExhaustedWithCountdown)
            Toggle("Notify when 5-hour allowance resets", isOn: $viewModel.settings.notifyFiveHourReset)
            Toggle("Notify when weekly allowance resets", isOn: $viewModel.settings.notifyWeeklyReset)
            Toggle("Enable usage warnings", isOn: $viewModel.settings.usageWarnings)
            HStack(spacing: 5) {
                Text("Warn at").foregroundStyle(.secondary)
                ForEach(viewModel.settings.warningThresholds.indices, id: \.self) { index in
                    TextField("Threshold", value: Binding(
                        get: { viewModel.settings.warningThresholds[index] },
                        set: { viewModel.settings.warningThresholds[index] = min(100, max(1, $0)) }
                    ), format: .number)
                    .frame(width: 34)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Warning threshold \(index + 1), percent")
                    Text("%")
                }
                Spacer(minLength: 0)
            }
            .disabled(!viewModel.settings.usageWarnings)
            Text("Countdowns use provider reset times. Reset alerts require fresh usage data.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.top, 8)
        .onChange(of: viewModel.settings.notificationsEnabled) { enabled in
            if enabled { Task { await viewModel.requestNotificationAuthorization() } }
        }
    }
}
