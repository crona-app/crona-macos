import Combine
import Foundation

@MainActor
final class GlanceModel: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var selectedIssue: DailyFocusIssue?
    @Published var showsCustomization = false
    @Published var showsSetup = false
    @Published var showsCapture = false
    @Published private(set) var isStarting = false
    @Published private(set) var commandInFlight = false
    @Published private(set) var error: String?
    @Published private(set) var setup = FocusSetupModel(initialState: .defaultState(estimateMinutes: nil, workedSeconds: 0))
    let day: PopoverDayModel
    let issues: DailyIssuesModel
    @Published var selectedHabit: HabitRowModel?
    @Published var previewIssue: DailyFocusIssue?
    let daily: DailyFocusService
    let habits: HabitsService
    let stats: PopoverStatsService
    private weak var appState: CompanionAppState?
    private let connection: DaemonConnectionService
    private let window: GlanceWindowPresenting
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var subscriptions: Set<AnyCancellable> = []
    lazy var capture = IssueCaptureModel(daemonConnection: connection, onImported: { [weak self] in
        await self?.refresh()
    })

    init(appState: CompanionAppState, window: GlanceWindowPresenting = GlanceWindowController()) {
        self.window = window
        self.appState = appState
        connection = appState.daemonConnection
        let day = PopoverDayModel(today: { [weak appState] in
            let date = appState?.daemonConnection.currentDate ?? ""
            return date.isEmpty ? DailyFocusService.todayString() : date
        })
        self.day = day
        issues = DailyIssuesModel(daemonConnection: connection, day: day,
            issueCreationService: appState.issueCreationService, tags: appState.tags, backgroundRefreshEnabled: false)
        daily = DailyFocusService(daemonConnection: connection, backgroundRefreshEnabled: false)
        habits = HabitsService(daemonConnection: connection, backgroundRefreshEnabled: false)
        stats = PopoverStatsService(daemonConnection: connection, backgroundRefreshEnabled: false)
        issues.$sections.dropFirst().sink { [weak self] sections in
            guard let self, let selected = previewIssue else { return }
            previewIssue = (sections.planned + sections.overdue + sections.upcoming + sections.inbox).first { $0.id == selected.id }
        }.store(in: &subscriptions)
        habits.$snapshot.dropFirst().sink { [weak self] snapshot in
            guard let self, snapshot.date == day.selectedDate, let selected = selectedHabit else { return }
            selectedHabit = snapshot.items.first { $0.id == selected.id }
        }.store(in: &subscriptions)
        day.onChange = { [weak self] _ in
            self?.previewIssue = nil
            self?.selectedHabit = nil
            self?.appState?.preferences.preferences.glance.lastDate = self?.day.selectedDate
            Task { await self?.refresh() }
        }
    }

    func reconcileWindowVisibility() {
        if isPresented && !window.isVisible { dismiss(restoreFocus: false) }
    }

    func toggle(appState: CompanionAppState) {
        reconcileWindowVisibility()
        if isPresented { dismiss(); return }
        guard !isBlocked else { return }
        let existingDetails = appState.popoverDetailsRoute
        appState.statusBarService.dismissPopup(animated: false)
        appState.popoverDetailsRoute = existingDetails
        let preferences = appState.preferences.preferences.glance
        day.select(preferences.rememberDate ? (preferences.lastDate ?? day.selectedDate) : appState.daemonConnection.currentDate)
        issues.section = DailySection(rawValue: preferences.startingSection) ?? .planned
        generation += 1
        isPresented = window.show(appState: appState, model: self)
        guard isPresented else { return }
        setBackgroundRefreshEnabled(true)
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.refresh() }
    }

    var isBlocked: Bool {
        guard let appState else { return true }
        return appState.windowService.breakScreensVisible || appState.windowService.hardLimitPopupVisible
    }

    var isSelectedDayAway: Bool {
        guard let state = appState else { return false }
        return day.isToday ? state.todayIsAway : day.isRecordedAway(in: state.coreSettingsService.settings)
    }

    var canChangeAwayMode: Bool {
        day.isToday && !isStarting && appState?.hasActiveFocusSession == false
            && connection.connectionState == .connected
    }

    func setAwayMode(_ enabled: Bool) async {
        guard canChangeAwayMode, let state = appState else { return }
        if enabled ? state.todayIsAway : !state.coreSettingsService.settings.awayModeEnabled { return }
        await state.coreSettingsService.setAwayMode(enabled)
    }

    func toggleCapture() {
        guard day.isToday, !isSelectedDayAway, appState?.hasActiveFocusSession != true else { return }
        showsSetup = false
        showsCapture.toggle()
    }

    /// Escape closes the open card first, then Glance itself.
    func handleEscape() {
        if showsCustomization { showsCustomization = false; return }
        if let state = appState {
            if state.endSession.isSheetPresented { state.endSession.cancel(); return }
            if state.issueActions.editor != nil { state.issueActions.cancel(); return }
            if state.tagEditor.isPresented { state.tagEditor.dismiss(); return }
            if state.issueCreator.isPresented { state.issueCreator.cancel(); return }
            if state.issueCapture.isPresented { state.issueCapture.dismiss(); return }
            if state.habitEditor.actionEditor != nil { state.habitEditor.cancelActionEditor(); return }
            if state.habitEditor.isPresented { state.habitEditor.cancel(); return }
            if state.popoverDetailsRoute != nil { state.dismissDetails(); return }
        }
        if showsSetup { showsSetup = false } else if showsCapture { showsCapture = false } else { dismiss() }
    }

    func dismiss(restoreFocus: Bool = true) {
        appState?.preferences.preferences.glance.lastDate = day.selectedDate
        showsCustomization = false
        generation += 1
        window.dismiss(restoreFocus: restoreFocus)
        isPresented = false
        refreshTask?.cancel()
        setBackgroundRefreshEnabled(false)
    }

    private func setBackgroundRefreshEnabled(_ enabled: Bool) {
        issues.setBackgroundRefreshEnabled(enabled)
        daily.setBackgroundRefreshEnabled(enabled)
        habits.setBackgroundRefreshEnabled(enabled)
        stats.setBackgroundRefreshEnabled(enabled)
    }

    func refresh() async {
        let date = day.selectedDate
        habits.selectedDate = date
        async let sections: Void = issues.refresh()
        async let issues: Void = daily.refresh(date: date)
        async let due: Void = habits.refresh(date: date)
        async let metrics: Void = stats.reconcileToDate(date)
        _ = await (issues, due, metrics, sections)
        guard date == day.selectedDate else { return }
        if previewIssue == nil && selectedHabit == nil,
           let activeID = appState?.timerService.snapshot.issueID {
            previewIssue = self.issues.allIssues.first { $0.id == activeID }
        }
    }

    func prepare(_ issue: DailyFocusIssue? = nil) {
        guard day.isToday, !isSelectedDayAway, !isStarting, appState?.hasActiveFocusSession != true else { return }
        if selectedIssue?.id != issue?.id {
            setup = FocusSetupModel(initialState: .defaultState(estimateMinutes: issue?.estimateMinutes, workedSeconds: issue?.workedSeconds ?? 0))
        }
        selectedIssue = issue
        showsCapture = false
        showsSetup = true
        error = nil
    }

    private var conflict: Bool {
        guard let state = appState else { return true }
        return state.isPopoverModalPresented || state.habitEditor.isPresented || state.isStartingFocus
            || state.selectedFocusIssue != nil || state.isAdhocStartSelected
    }

    func start() async {
        guard day.isToday, !isStarting, let state = appState, let config = setup.configuration else { return }
        guard !conflict else { error = "Finish the open Crona flow before starting focus."; return }
        guard connection.connectionState == .connected else { error = "Crona is disconnected."; return }
        guard !state.hasActiveFocusSession, !state.todayIsAway else {
            error = "End the active session or turn off Away Mode before starting focus."; return
        }
        isStarting = true
        error = nil
        let openedGeneration = generation
        defer { isStarting = false }
        do {
            _ = try await connection.withClient { try await $0.timerStart(config.startRequest(for: self.selectedIssue)) }
            await state.timerService.refresh()
            await state.contextService.refresh()
            showsSetup = false
            selectedIssue = nil
            if openedGeneration == generation { await refresh() }
        } catch { self.error = error.localizedDescription }
    }

    func importCapture() async {
        guard day.isToday else { error = "Return to Today to capture issues."; return }
        guard !isSelectedDayAway else { error = "Turn off Away Mode before capturing issues."; return }
        guard !conflict else { error = "Finish the open Crona flow before capturing issues."; return }
        let openedGeneration = generation
        if await capture.importAll(), openedGeneration == generation { showsCapture = false }
    }

    func timerCommand(advance: Bool = false) async {
        guard !commandInFlight, let state = appState else { return }
        commandInFlight = true
        error = nil
        defer { commandInFlight = false }
        let presentation = TimerPresentation.from(state.timerService.snapshot)
        do {
            if advance && presentation.canAdvance { try await state.timerService.advanceTimer() }
            else if !advance && presentation.canPause { try await state.timerService.pauseTimer() }
            else if !advance && presentation.canResume { try await state.timerService.resumeTimer() }
        } catch { self.error = error.localizedDescription }
    }
}
