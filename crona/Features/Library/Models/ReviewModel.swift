import Combine
import Foundation

@MainActor
final class ReviewModel: ObservableObject {
    @Published var period: ReviewPeriod = .week
    @Published var anchor: String
    @Published private(set) var metrics: [CronaDailyMetricsDay] = []
    @Published private(set) var checkIns: [CronaDailyCheckIn] = []
    @Published private(set) var scores: [CronaFocusScoreRangeDay] = []
    @Published private(set) var plan: CronaPlanWindow?
    @Published private(set) var previousPlan: CronaPlanWindow?
    @Published private(set) var estimates: CronaEstimateSummary?
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadedRange: ReviewRange?
    private let connection: DaemonConnectionService
    private let settings: () -> CronaCoreSettings
    private var observer: FeatureRefreshObserver?
    private var generation = UUID()
    private var visible = false
    private var stale = true

    init(connection: DaemonConnectionService, settings: @escaping () -> CronaCoreSettings) {
        self.connection = connection
        self.settings = settings
        anchor = connection.currentDate.isEmpty ? DailyFocusService.todayString() : connection.currentDate
        observer = FeatureRefreshObserver(
            connection: connection,
            events: [
                "checkin.updated", "checkin.deleted", "session.ended", "session.history_changed", "issue.updated",
                "issue.created", "issue.deleted", "habit.completed", "habit.uncompleted", "settings.changed",
            ]
        ) { [weak self] in self?.invalidate() }
    }

    var today: String { connection.currentDate.isEmpty ? DailyFocusService.todayString() : connection.currentDate }
    var range: ReviewRange { period.range(anchor: min(anchor, today), today: today, weekStart: settings().weekStart) }
    var canGoNext: Bool { range.end < today }
    var totalWork: Int { metrics.reduce(0) { $0 + $1.workedSeconds } }
    var averageWork: Int { totalWork / max(1, range.dates.count) }
    var totalSessions: Int { metrics.reduce(0) { $0 + $1.sessionCount } }
    var completionDelta: Double? {
        guard let current = plan?.completionRate, let previous = previousPlan?.completionRate else { return nil }
        return (current - previous) * 100
    }
    func isAway(_ date: String) -> Bool { settings().isHistoricalAwayDate(date) }
    func shift(_ amount: Int) { anchor = min(period.shifted(anchor, by: amount), today) }
    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if value && (stale || loadedRange != range) { Task { await refresh() } }
    }
    func invalidate() {
        generation = UUID()
        stale = true
        isLoading = false
        if visible { Task { await refresh() } }
    }

    /// Sections load independently so one unsupported endpoint cannot erase the rest.
    func refresh(section: String? = nil) async {
        let token = UUID()
        generation = token
        let requested = range
        if loadedRange != requested {
            metrics = []
            checkIns = []
            scores = []
            plan = nil
            previousPlan = nil
            estimates = nil
            errors = [:]
        }
        loadedRange = requested
        isLoading = true
        defer { if generation == token { isLoading = false } }
        let sections = section.map { [$0] } ?? ["Work", "Wellbeing", "Focus", "Plan", "Comparison", "Estimates"]
        for name in sections {
            guard generation == token, range == requested else { return }
            errors[name] = nil
            do {
                switch name {
                case "Work":
                    let value = try await connection.withClient {
                        try await $0.metricsRange(start: requested.start, end: requested.end)
                    }
                    guard generation == token, range == requested else { return }
                    metrics = value
                case "Wellbeing":
                    let value = try await connection.withClient {
                        try await $0.checkInRange(start: requested.start, end: requested.end)
                    }
                    guard generation == token, range == requested else { return }
                    checkIns = value
                case "Focus":
                    let value = try await connection.withClient {
                        try await $0.dashboardFocusScoreRange(start: requested.start, end: requested.end)
                    }
                    guard generation == token, range == requested else { return }
                    scores = value
                case "Plan":
                    let value = try await connection.withClient {
                        try await $0.planWindow(start: requested.start, end: requested.end)
                    }
                    guard generation == token, range == requested else { return }
                    plan = value
                case "Comparison":
                    let value = try await connection.withClient {
                        try await $0.planWindow(start: requested.previousStart, end: requested.previousEnd)
                    }
                    guard generation == token, range == requested else { return }
                    previousPlan = value
                case "Estimates":
                    let value = try await connection.withClient {
                        try await $0.estimateSummary(start: requested.start, end: requested.end)
                    }
                    guard generation == token, range == requested else { return }
                    estimates = value
                default: break
                }
            } catch {
                guard generation == token, range == requested else { return }
                errors[name] = error.localizedDescription
            }
        }
        stale = false
    }
}
