import Combine
import Foundation

@MainActor
final class DailyActivityModel: ObservableObject {
    @Published private(set) var updates: [CronaIssueOperation] = []
    @Published private(set) var issues: [CronaIssue] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var loadedDate: String?
    private let connection: DaemonConnectionService
    private let day: PopoverDayModel
    private var observer: FeatureRefreshObserver?
    private var daySubscription: AnyCancellable?
    private var generation = UUID()
    private var visible = false
    private var stale = true

    init(connection: DaemonConnectionService, day: PopoverDayModel) {
        self.connection = connection
        self.day = day
        observer = FeatureRefreshObserver(
            connection: connection,
            events: [
                "issue.created", "issue.updated", "issue.deleted", "issue.restored", "session.ended",
            ]
        ) { [weak self] in self?.invalidate() }
        daySubscription = day.$selectedDate.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.updates = []
            self?.issues = []
            self?.loadedDate = nil
            self?.invalidate()
        }
    }
    func invalidate() {
        generation = UUID()
        isLoading = false
        stale = true
        if visible { Task { await refresh() } }
    }
    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if value && (stale || loadedDate != day.selectedDate) { Task { await refresh() } }
    }
    func refresh() async {
        let token = UUID()
        generation = token
        let date = day.selectedDate
        let timezone = connection.timezone
        isLoading = true
        error = nil
        defer { if generation == token { isLoading = false } }
        do {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timezone) ?? .current
            let components = LibraryDates.calendar.dateComponents([.year, .month, .day], from: LibraryDates.date(date))
            guard let start = calendar.date(from: components),
                let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { return }
            let since = ISO8601DateFormatter().string(from: start.addingTimeInterval(-1))
            let ops = try await connection.withClient { try await $0.operations(since: since) }
            let allIssues = try await connection.withClient { try await $0.listAllIssues() }
            guard generation == token, date == day.selectedDate else { return }
            updates = Self.updates(ops, start: start, end: end)
            issues = allIssues
            loadedDate = date
            stale = false
        } catch {
            guard generation == token else { return }
            self.error = error.localizedDescription
        }
    }
    static func updates(_ ops: [CronaIssueOperation], start: Date, end: Date) -> [CronaIssueOperation] {
        Array(
            ops.filter {
                guard $0.entity == "issue", let date = LibraryDates.timestamp($0.timestamp) else { return false }
                return date >= start && date < end
            }.sorted {
                (LibraryDates.timestamp($0.timestamp) ?? .distantPast)
                    > (LibraryDates.timestamp($1.timestamp) ?? .distantPast)
            }.prefix(7))
    }
    func issue(for operation: CronaIssueOperation) -> CronaIssue? {
        issues.first { String($0.id) == operation.entityID }
    }
    func title(for operation: CronaIssueOperation) -> String {
        issue(for: operation)?.title ?? operation.payload?["title"]?.stringValue ?? "Issue #\(operation.entityID)"
    }
}
