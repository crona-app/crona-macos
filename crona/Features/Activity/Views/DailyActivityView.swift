import SwiftUI

struct DailyActivityView: View {
    let appState: CompanionAppState
    @ObservedObject private var model: DailyActivityModel
    @ObservedObject private var connection: DaemonConnectionService

    init(appState: CompanionAppState) {
        self.appState = appState
        model = appState.dailyActivity
        connection = appState.daemonConnection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recent activity", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.borderless).help("Refresh activity")
                    .accessibilityLabel("Refresh activity")
                }
            }
            if let error = model.error {
                LibraryErrorView(message: error) { Task { await model.refresh() } }
            } else if model.updates.isEmpty && !model.isLoading {
                Text("No issue changes on this day.").font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            VStack(spacing: 0) {
                ForEach(model.updates) { operation in
                    DailyActivityRow(
                        operation: operation,
                        title: model.title(for: operation),
                        time: LibraryDates.clock(operation.timestamp, timezone: connection.timezone) ?? "—",
                        isLast: operation.id == model.updates.last?.id,
                        openIssue: model.issue(for: operation).map { issue in
                            { appState.openActivityIssueDetails(DailyFocusIssue(issue: issue)) }
                        }
                    )
                }
            }
        }
        .padding(14)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 14))
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
    }
}
