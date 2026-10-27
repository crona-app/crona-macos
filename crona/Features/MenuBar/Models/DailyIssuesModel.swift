import Combine
import Foundation
import OSLog

/// Planned, Overdue and Upcoming issues for the shared popover day.
@MainActor
final class DailyIssuesModel: ObservableObject {
    private static let refreshEvents: Set<String> = [
        "session.history_changed", "session.started", "session.stopped", "session.ended",
        "context.issue.changed", "issue.updated", "issue.created", "issue.deleted",
    ]

    private let daemonConnection: DaemonConnectionService
    private let day: PopoverDayModel
    private var eventObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.crona.macos", category: "dailyIssues")

    @Published private(set) var sections = DailyIssueSections()
    @Published var section: DailySection = .planned
    @Published private(set) var isLoading = false

    init(daemonConnection: DaemonConnectionService, day: PopoverDayModel) {
        self.daemonConnection = daemonConnection
        self.day = day
        eventObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonEventReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CronaProtocolEvent,
                Self.refreshEvents.contains(event.type)
            else { return }
            Task { await self?.refresh() }
        }
    }

    isolated deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
    }

    var allIssues: [DailyFocusIssue] {
        sections.planned + sections.overdue + sections.upcoming
    }

    func refresh() async {
        let date = day.selectedDate
        isLoading = true
        defer { isLoading = false }
        do {
            async let issues = daemonConnection.withClient { try await $0.listAllIssues() }
            async let plan = daemonConnection.withClient { try await $0.dailyPlanGet(date: date) }
            let built = DailyIssueSections.build(issues: try await issues, plan: try await plan, date: date)
            // A newer day may have been picked while this one loaded.
            guard date == day.selectedDate else { return }
            sections = built
        } catch {
            logger.error("Daily issues refresh failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}
