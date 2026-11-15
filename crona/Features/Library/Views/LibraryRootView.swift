import SwiftUI

struct LibraryRootView: View {
    let appState: CompanionAppState
    @ObservedObject private var navigation: LibraryNavigationModel
    @ObservedObject private var connection: DaemonConnectionService

    init(appState: CompanionAppState) {
        self.appState = appState
        navigation = appState.libraryNavigation
        connection = appState.daemonConnection
    }

    var body: some View {
        NavigationSplitView {
            List(LibraryDestination.allCases, selection: $navigation.destination) { destination in
                Label(destination.rawValue, systemImage: destination.icon).tag(destination)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
        } detail: {
            VStack(spacing: 0) {
                if connection.connectionState != .connected {
                    Label("Daemon disconnected. Reconnect to refresh or edit.", systemImage: "wifi.slash")
                        .font(.callout).padding(10).frame(maxWidth: .infinity).background(.regularMaterial)
                }
                switch navigation.destination {
                case .checkIns: CheckInHistoryView(appState: appState)
                case .review: ReviewView(appState: appState)
                }
            }
            .navigationTitle("Crona Library")
            .navigationSubtitle(navigation.destination.rawValue)
        }
        .companionAppearance(appState)
    }
}

struct LibraryErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Spacer()
            Button("Retry", action: retry)
        }.font(.callout).padding(10)
    }
}

struct CheckInTimestampsView: View {
    let entry: CronaDailyCheckIn
    let timezone: String
    let settings: CronaCoreSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let recorded = LibraryDates.clock(
                entry.createdAt, timezone: timezone, includeDate: true, settings: settings)
            {
                Text("Recorded \(recorded)")
            }
            if entry.updatedAt != entry.createdAt,
                let updated = LibraryDates.clock(
                    entry.updatedAt, timezone: timezone, includeDate: true, settings: settings)
            {
                Text("Updated \(updated)")
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
