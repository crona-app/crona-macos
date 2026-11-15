import Combine
import Foundation

struct HabitDayOutcome: Identifiable, Equatable {
    let date: String
    var status = ""
    var minutes = 0
    var notes: [String] = []
    var id: String { date }
}

@MainActor
final class HabitHistoryModel: ObservableObject {
    @Published private(set) var records: [CronaHabitCompletion] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    private let connection: DaemonConnectionService
    private var observer: FeatureRefreshObserver?
    private var generation = UUID()
    private var visible = false
    private var stale = true

    init(connection: DaemonConnectionService) {
        self.connection = connection
        observer = FeatureRefreshObserver(
            connection: connection,
            events: [
                "habit.created", "habit.updated", "habit.deleted", "habit.completed", "habit.uncompleted",
                "session.ended",
            ]
        ) { [weak self] in
            guard let self else { return }
            generation = UUID()
            stale = true
            isLoading = false
            if visible { Task { await refresh() } }
        }
    }

    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if value && stale { Task { await refresh() } }
    }

    func refresh() async {
        let token = UUID()
        generation = token
        isLoading = true
        error = nil
        defer { if generation == token { isLoading = false } }
        do {
            let value = try await connection.withClient { try await $0.habitHistory() }
            guard generation == token else { return }
            records = value
            stale = false
        } catch {
            guard generation == token else { return }
            self.error = error.localizedDescription
        }
    }

    func outcomes(habitID: Int64, through date: String) -> [HabitDayOutcome] {
        Self.outcomes(records, habitID: habitID, through: date)
    }

    static func outcomes(_ records: [CronaHabitCompletion], habitID: Int64, through date: String) -> [HabitDayOutcome] {
        var days: [String: HabitDayOutcome] = [:]
        for record in records where record.habitID == habitID && record.date <= date {
            var day = days[record.date] ?? HabitDayOutcome(date: record.date)
            day.minutes += record.durationMinutes ?? 0
            if !record.status.isEmpty && day.status != "completed" { day.status = record.status }
            if let notes = record.notes, !notes.isEmpty { day.notes.append(notes) }
            days[record.date] = day
        }
        return days.values.sorted { $0.date > $1.date }
    }

    static func hitRate(_ outcomes: [HabitDayOutcome], through date: String, days: Int) -> Double? {
        let start = LibraryDates.adding(1 - days, to: date)
        let recorded = outcomes.filter { $0.date >= start && $0.date <= date && !$0.status.isEmpty }
        guard !recorded.isEmpty else { return nil }
        return Double(recorded.filter { $0.status == "completed" }.count) / Double(recorded.count)
    }
}
