import Combine
import Foundation
import OSLog

/// Focused time per tag for the Stats tab: the shown day, and its week from Monday up to that day.
@MainActor
final class TagFocusModel: ObservableObject {
    static let rowLimit = 5
    private static let refreshEvents: Set<String> = [
        "session.history_changed", "session.ended", "issue.updated", "tags.changed",
    ]

    private let daemonConnection: DaemonConnectionService
    private var eventObserver: NSObjectProtocol?
    private var date: String?
    private let logger = Logger(subsystem: "com.crona.macos", category: "tagFocus")

    @Published private(set) var today: [CronaTimeDistributionRow] = []
    @Published private(set) var week: [CronaTimeDistributionRow] = []

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
        eventObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonEventReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CronaProtocolEvent,
                Self.refreshEvents.contains(event.type)
            else { return }
            Task { @MainActor in
                guard let self, let date = self.date else { return }
                await self.refresh(date: date)
            }
        }
    }

    isolated deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
    }

    func refresh(date: String) async {
        self.date = date
        let start = Self.weekStart(for: date)
        do {
            async let day = daemonConnection.withClient {
                try await $0.dashboardDistribution(start: date, end: date, groupBy: "tag")
            }
            async let range = daemonConnection.withClient {
                try await $0.dashboardDistribution(start: start, end: date, groupBy: "tag")
            }
            let (todaySummary, weekSummary) = try await (day, range)
            // A newer day may have been picked while this one loaded.
            guard self.date == date else { return }
            today = Self.top(todaySummary.rows)
            week = Self.top(weekSummary.rows)
        } catch {
            logger.error("Tag distribution failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func weekStart(for date: String) -> String {
        guard let day = CronaCalendarDate.date(from: date) else { return date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        // Gregorian weekday: Sunday is 1, Monday is 2.
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        return CronaCalendarDate.adding(days: -daysSinceMonday, to: date) ?? date
    }

    private static func top(_ rows: [CronaTimeDistributionRow]) -> [CronaTimeDistributionRow] {
        Array(rows.filter { $0.workedSeconds > 0 }.sorted { $0.workedSeconds > $1.workedSeconds }.prefix(rowLimit))
    }
}
