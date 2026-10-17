import Combine
import Foundation

@MainActor
final class HabitEditorModel: ObservableObject {
    @Published var name = ""
    @Published var description = ""
    @Published var destinationID: Int64?
    @Published var scheduleType = "daily"
    @Published var weekdays: Set<Int> = []
    @Published var target = ""
    @Published var active = true
    @Published var error: String?
    @Published private(set) var isPresented = false
    @Published private(set) var habitBeingEdited: HabitRowModel?
    @Published var actionEditor: HabitActionEditor?

    private let daemonConnection: DaemonConnectionService
    private let habitsService: HabitsService
    private let issueCreationService: IssueCreationService
    private let contextService: ContextService
    private let canPresent: () -> Bool

    init(
        daemonConnection: DaemonConnectionService,
        habitsService: HabitsService,
        issueCreationService: IssueCreationService,
        contextService: ContextService,
        canPresent: @escaping () -> Bool
    ) {
        self.daemonConnection = daemonConnection
        self.habitsService = habitsService
        self.issueCreationService = issueCreationService
        self.contextService = contextService
        self.canPresent = canPresent
    }

    func presentCreator() {
        guard daemonConnection.connectionState == .connected,
            canPresent(), actionEditor == nil
        else { return }
        habitBeingEdited = nil
        habitsService.clearManagementError()
        name = ""
        description = ""
        destinationID = contextService.snapshot.streamID
        scheduleType = "daily"
        weekdays = []
        target = ""
        active = true
        error = nil
        isPresented = true
    }

    func presentEditor(for habit: HabitRowModel) {
        guard daemonConnection.connectionState == .connected,
            canPresent(), actionEditor == nil
        else { return }
        habitsService.clearManagementError()
        habitBeingEdited = habit
        name = habit.name
        description = habit.description ?? ""
        destinationID = issueCreationService.destinations.first {
            $0.repoName == habit.repoName && $0.streamName == habit.streamName
        }?.streamID
        scheduleType = habit.scheduleType ?? "daily"
        weekdays = Set(habit.weekdays)
        target = habit.targetMinutes.map(MenuBarTextFormatter.formatMinutes) ?? ""
        active = habit.active
        error = nil
        isPresented = true
        Task { await issueCreationService.loadDestinations() }
    }

    func cancel() {
        guard !habitsService.isManagingHabit else { return }
        habitsService.clearManagementError()
        habitBeingEdited = nil
        isPresented = false
    }

    func presentDelete(for habit: HabitRowModel) {
        habitsService.clearManagementError()
        actionEditor = .delete(habit: habit)
    }

    func submit() {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else {
            error = "Enter a habit name."
            return
        }
        let targetText = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .success(let targetMinutes) = FlexibleDurationParser.optionalMinutes(targetText),
            targetMinutes == nil || targetMinutes! >= 0
        else {
            error = "Enter a valid target duration."
            return
        }
        let schedule: String
        let weekdays: [Int]
        switch scheduleType {
        case "weekly":
            guard !self.weekdays.isEmpty else {
                error = "Select at least one weekday."
                return
            }
            schedule = "weekly"
            weekdays = self.weekdays.sorted()
        case "weekdays":
            schedule = "weekdays"
            weekdays = []
        default:
            schedule = "daily"
            weekdays = []
        }
        guard let streamID = destinationID else {
            error = "Choose a repository and stream."
            return
        }
        error = nil
        let refreshDate = habitsService.snapshot.date.isEmpty ? DailyFocusService.todayString() : habitsService.snapshot.date
        if let habit = habitBeingEdited {
            Task {
                let succeeded = await habitsService.update(
                    CronaUpdateHabitRequest(
                        id: habit.id,
                        name: name,
                        description: description.isEmpty ? nil : description,
                        scheduleType: schedule,
                        weekdays: weekdays,
                        targetMinutes: targetMinutes,
                        active: active
                    ),
                    refreshDate: refreshDate
                )
                if succeeded { self.habitBeingEdited = nil; self.isPresented = false }
            }
        } else {
            Task {
                let succeeded = await habitsService.create(
                    CronaCreateHabitRequest(
                        streamID: streamID,
                        name: name,
                        description: description.isEmpty ? nil : description,
                        scheduleType: schedule,
                        weekdays: weekdays,
                        targetMinutes: targetMinutes
                    ),
                    refreshDate: refreshDate
                )
                if succeeded { self.isPresented = false }
            }
        }
    }

    func submitActionEditor() {
        guard case .delete(let habit) = actionEditor else { return }
        let refreshDate = habitsService.snapshot.date.isEmpty ? DailyFocusService.todayString() : habitsService.snapshot.date
        Task {
            if await habitsService.delete(habit, refreshDate: refreshDate) {
                actionEditor = nil
            }
        }
    }

    func cancelActionEditor() {
        guard !habitsService.isManagingHabit else { return }
        actionEditor = nil
        habitsService.clearManagementError()
    }

    func complete(_ habit: HabitRowModel) {
        Task { await habitsService.complete(habit) }
    }

    func log(_ habit: HabitRowModel, durationMinutes: Int) {
        Task {
            await habitsService.complete(
                habit,
                durationMinutes: max(1, durationMinutes)
            )
        }
    }

    func fail(_ habit: HabitRowModel) {
        Task { await habitsService.fail(habit) }
    }

    func clearCompletion(_ habit: HabitRowModel) {
        Task { await habitsService.clearCompletion(habit) }
    }
}
