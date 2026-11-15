import Combine
import Foundation

@MainActor
final class CheckInHistoryModel: ObservableObject {
    @Published private(set) var records: [CronaDailyCheckIn] = []
    @Published var search = ""
    @Published var selectedDate: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?
    private let connection: DaemonConnectionService
    private let settings: () -> CronaCoreSettings
    private let canMutate: () -> Bool
    private let onChanged: @MainActor (String) async -> Void
    private var observer: FeatureRefreshObserver?
    private var generation = UUID()
    private var visible = false
    private var stale = true

    init(
        connection: DaemonConnectionService, settings: @escaping () -> CronaCoreSettings = { CronaCoreSettings() },
        canMutate: @escaping () -> Bool,
        onChanged: @escaping @MainActor (String) async -> Void
    ) {
        self.connection = connection
        self.settings = settings
        self.canMutate = canMutate
        self.onChanged = onChanged
        observer = FeatureRefreshObserver(connection: connection, events: ["checkin.updated", "checkin.deleted"]) {
            [weak self] in
            self?.invalidate()
        }
    }

    var mutationsAllowed: Bool { canMutate() && connection.connectionState == .connected && !isSaving }
    var filtered: [CronaDailyCheckIn] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { entry in
            let fields = [
                entry.date, CronaDateDisplayFormatter.string(fromISODate: entry.date, settings: settings()),
                String(entry.mood), String(entry.energy), entry.sleepHours.map { String($0) } ?? "",
                entry.sleepScore.map(String.init) ?? "", entry.screenTimeMinutes.map(String.init) ?? "",
                entry.notes ?? "",
            ]
            return query.isEmpty || fields.joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }
    var selected: CronaDailyCheckIn? { records.first { $0.date == selectedDate } }

    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if value && stale { Task { await refresh() } }
    }

    func invalidate() {
        generation = UUID()
        stale = true
        isLoading = false
        if visible { Task { await refresh() } }
    }

    func refresh() async {
        let token = UUID()
        generation = token
        isLoading = true
        error = nil
        defer { if generation == token { isLoading = false } }
        do {
            let result = try await connection.withClient { try await $0.checkInRange() }
            guard generation == token else { return }
            records = result.sorted { $0.date > $1.date }
            stale = false
            reconcileSelection()
        } catch {
            guard generation == token else { return }
            self.error = error.localizedDescription
        }
    }

    func reconcileSelection() {
        if !filtered.contains(where: { $0.date == selectedDate }) { selectedDate = filtered.first?.date }
    }

    @discardableResult
    func save(_ request: CronaDailyCheckInUpsertRequest, originalDate: String) async -> Bool {
        guard mutationsAllowed, request.date == originalDate else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            _ = try await connection.withClient { try await $0.checkInUpsert(request) }
            await refresh()
            await onChanged(request.date)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(date: String) async {
        guard mutationsAllowed else { return }
        let indices = filtered.map(\.date)
        let index = indices.firstIndex(of: date) ?? 0
        let next = indices.dropFirst(index + 1).first ?? indices.prefix(index).last
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            _ = try await connection.withClient { try await $0.checkInDelete(date: date) }
            if selectedDate == date { selectedDate = next }
            await refresh()
            await onChanged(date)
        } catch { self.error = error.localizedDescription }
    }
}
