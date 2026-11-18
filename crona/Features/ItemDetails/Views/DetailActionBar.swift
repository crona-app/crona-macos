import SwiftUI

/// Reserves space below the scrollable details so the actions never cover content.
struct DetailActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            Divider()
            content()
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

struct IssueDetailActionBar: View {
    let appState: CompanionAppState
    let issue: DailyFocusIssue

    var body: some View {
        DetailActionBar {
            HStack(spacing: 8) {
                Menu {
                    ForEach(CronaIssueStatus.allCases) { status in
                        Button {
                            appState.dismissDetails()
                            appState.issueActions.requestStatusChange(issue: issue, status: status)
                        } label: {
                            Label(status.title, systemImage: status.systemImage)
                        }
                    }
                } label: {
                    Label("Status", systemImage: "arrow.triangle.2.circlepath")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button {
                    appState.dismissDetails()
                    appState.issueActions.presentManualSession(for: issue)
                } label: {
                    Label("Log", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                .help("Log a session")
                Button {
                    appState.dismissDetails()
                    appState.selectFocusIssue(issue)
                } label: {
                    Label("Start Focus", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
    }
}
