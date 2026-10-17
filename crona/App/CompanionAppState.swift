import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI

enum SettingsDestination: String, CaseIterable, Hashable, Identifiable {
    case general
    case away
    case menuBar
    case daySchedule
    case smartPause
    case breakScreen
    case notifications
    case advanced
    case about
    #if DEBUG
        case developer
    #endif

    var id: String { rawValue }
}

enum EndSessionPresentationSource: Equatable {
    case menuPopover
    case timerHUD
    case hardLimitPopup
    case inactivityPopup
}

enum IssueActionEditor: Equatable {
    case status(issue: DailyFocusIssue, status: CronaIssueStatus)
    case dueDate(issue: DailyFocusIssue)
    case manualSession(issue: DailyFocusIssue)
    case delete(issue: DailyFocusIssue)
}

enum HabitActionEditor: Equatable {
    case delete(habit: HabitRowModel)
}

struct SmartPauseResumeNotice: Equatable {
    let sessionID: String
    let resumedAt: Date
}

struct IssueCreationSuccess: Equatable {
    let issue: DailyFocusIssue
    let plannedForToday: Bool
}

enum IssueCreationFollowUp: Hashable {
    case close
    case more
    case focus
}

#if DEBUG
    enum DeveloperPreviewKind: Equatable {
        case hardLimit
        case inactivity
        case breakScreen
    }
#endif

@MainActor
final class CompanionAppState: ObservableObject {
    let logger = Logger(subsystem: "com.crona.macos", category: "app")

    let preferences: PreferencesService
    let kernelDiscovery: KernelDiscoveryService
    let notificationService: NotificationService
    let alertSettingsService: AlertSettingsService
    let dayBoundarySettingsService: DayBoundarySettingsService
    let coreSettingsService: CoreSettingsService
    let launchAtLoginService: LaunchAtLoginService
    let daemonConnection: DaemonConnectionService
    let diagnosticsService: DiagnosticsService
    let timerService: TimerService
    let contextService: ContextService
    let dailyFocusService: DailyFocusService
    let issueActionsService: IssueActionsService
    let issueCreationService: IssueCreationService
    let habitsService: HabitsService
    let wellbeingService: WellbeingService
    let popoverStatsService: PopoverStatsService
    let hardLimitCountdownService: HardLimitCountdownService
    let inactivityPopupCountdownService: HardLimitCountdownService
    let windowService: WindowService
    let statusBarService: StatusBarService
    let settingsShortcutService: SettingsShortcutService
    let smartPauseService: SmartPauseService
    let breakScreenService: BreakScreenService
    let userActivityMonitor: UserActivityMonitor
    let appUpdateService: AppUpdateService
    private(set) lazy var endSession = EndSessionModel(
        daemonConnection: daemonConnection,
        timerService: timerService,
        contextService: contextService,
        dailyFocusService: dailyFocusService,
        habitsService: habitsService,
        popoverStatsService: popoverStatsService,
        issueCreationService: issueCreationService,
        windowService: windowService,
        handlesConfirmInPreview: { [weak self] in
            #if DEBUG
                if let self, self.isDeveloperPreviewActive {
                    self.dismissDeveloperPreviews()
                    return true
                }
            #endif
            return false
        },
        onFinalized: { [weak self] in
            guard let self else { return }
            selectedFocusIssue = nil
            popups.finalizePopups(forSessionID: nil)
        }
    )
    private(set) lazy var popups: PopupCoordinator = {
        let popups = PopupCoordinator(
            daemonConnection: daemonConnection,
            timerService: timerService,
            contextService: contextService,
            preferences: preferences,
            windowService: windowService,
            endSession: endSession,
            hardLimitCountdownService: hardLimitCountdownService,
            inactivityPopupCountdownService: inactivityPopupCountdownService
        )
        #if DEBUG
            popups.developerPreviewKind = { [weak self] in self?.developerPreviewKind }
            popups.dismissDeveloperPreviews = { [weak self] in self?.dismissDeveloperPreviews() }
        #endif
        return popups
    }()
    private(set) lazy var issueActions = IssueActionEditorModel(
        daemonConnection: daemonConnection,
        issueActionsService: issueActionsService,
        dailyFocusService: dailyFocusService,
        onIssueDeleted: { [weak self] issueID in
            if self?.selectedFocusIssue?.id == issueID { self?.selectedFocusIssue = nil }
        }
    )
    private(set) lazy var habitEditor = HabitEditorModel(
        daemonConnection: daemonConnection,
        habitsService: habitsService,
        issueCreationService: issueCreationService,
        contextService: contextService,
        canPresent: { [weak self] in
            guard let self else { return false }
            return !endSession.isSheetPresented && issueActions.editor == nil
        }
    )
    private(set) lazy var issueCreator = IssueCreatorModel(
        daemonConnection: daemonConnection,
        issueCreationService: issueCreationService,
        issueActionsService: issueActionsService,
        dailyFocusService: dailyFocusService,
        contextService: contextService,
        canPresent: { [weak self] in
            guard let self else { return false }
            return !endSession.isSheetPresented && issueActions.editor == nil
        },
        hasActiveFocusSession: { [weak self] in self?.hasActiveFocusSession ?? false },
        focusIssue: { [weak self] issue in
            self?.selectedPopoverTab = .now
            self?.selectedFocusIssue = issue
        }
    )
    private var cancellables: Set<AnyCancellable> = []
    private var daemonEventObserver: NSObjectProtocol?
    private var daemonConnectObserver: NSObjectProtocol?
    private var presentationTimer: Timer?
    private var settingsSceneAction: (() -> Void)?
    @Published var popoverDetailsRoute: PopoverDetailRoute?
    @Published var isAdhocStartSelected = false
    @Published var isStartingFocus = false
    @Published var focusStartError: String?
    @Published var selectedFocusIssue: DailyFocusIssue?
    @Published var selectedPopoverTab: PopoverTab = .now
    @Published var isStatsCalendarPresented = false
    @Published private(set) var selectedSettingsDestination: SettingsDestination = .general
    #if DEBUG
        @Published var developerPreviewKind: DeveloperPreviewKind?
    #endif

    init(daemonConnection injectedDaemonConnection: DaemonConnectionService? = nil) {
        let preferences = PreferencesService()
        let kernelDiscovery = KernelDiscoveryService(configLoader: CronaConfigLoader())
        let notificationService = NotificationService()
        let launchAtLoginService = LaunchAtLoginService()
        let daemonConnection = injectedDaemonConnection ?? DaemonConnectionService(kernelDiscovery: kernelDiscovery)
        let contextService = ContextService(daemonConnection: daemonConnection)
        let timerService = TimerService(daemonConnection: daemonConnection)
        let dailyFocusService = DailyFocusService(daemonConnection: daemonConnection)
        let issueActionsService = IssueActionsService(
            daemonConnection: daemonConnection,
            dailyFocusService: dailyFocusService
        )
        let issueCreationService = IssueCreationService(daemonConnection: daemonConnection)
        let habitsService = HabitsService(daemonConnection: daemonConnection)
        let wellbeingService = WellbeingService(daemonConnection: daemonConnection)
        let popoverStatsService = PopoverStatsService(daemonConnection: daemonConnection)
        let diagnosticsService = DiagnosticsService(
            daemonConnection: daemonConnection,
            kernelDiscovery: kernelDiscovery
        )
        let alertSettingsService = AlertSettingsService(daemonConnection: daemonConnection)
        let dayBoundarySettingsService = DayBoundarySettingsService(
            daemonConnection: daemonConnection)
        let coreSettingsService = CoreSettingsService(daemonConnection: daemonConnection)
        let appUpdateService = AppUpdateService(preferences: preferences)
        let userActivityMonitor = UserActivityMonitor()

        self.preferences = preferences
        self.kernelDiscovery = kernelDiscovery
        self.notificationService = notificationService
        self.alertSettingsService = alertSettingsService
        self.dayBoundarySettingsService = dayBoundarySettingsService
        self.coreSettingsService = coreSettingsService
        self.userActivityMonitor = userActivityMonitor
        self.launchAtLoginService = launchAtLoginService
        self.daemonConnection = daemonConnection
        self.contextService = contextService
        self.timerService = timerService
        self.dailyFocusService = dailyFocusService
        self.issueActionsService = issueActionsService
        self.issueCreationService = issueCreationService
        self.habitsService = habitsService
        self.wellbeingService = wellbeingService
        self.popoverStatsService = popoverStatsService
        self.hardLimitCountdownService = HardLimitCountdownService()
        self.inactivityPopupCountdownService = HardLimitCountdownService()
        self.diagnosticsService = diagnosticsService
        let windowService = WindowService()
        let statusBarService = StatusBarService()
        let settingsShortcutService = SettingsShortcutService()
        self.windowService = windowService
        self.statusBarService = statusBarService
        self.settingsShortcutService = settingsShortcutService
        self.smartPauseService = SmartPauseService(
            preferences: preferences,
            timerController: timerService
        )
        self.breakScreenService = BreakScreenService(
            preferences: preferences,
            timerService: timerService,
            windowService: windowService
        )
        self.appUpdateService = appUpdateService

        self.smartPauseService.setAutomaticResumeHandler { [weak self] snapshot in
            self?.popups.presentSmartPauseResumeNotice(for: snapshot)
        }

        notificationService.configure(
            daemonConnection: daemonConnection,
            onOpenCrona: { [weak statusBarService] in
                statusBarService?.showPopupFromNotification()
            },
            onOpenTUI: { [weak self] in
                self?.openTUI()
            },
            onAdvanceTimer: { [weak timerService, weak statusBarService] expected in
                Task { @MainActor in
                    await timerService?.refresh()
                    guard timerService?.snapshot.readySegmentType == expected else {
                        statusBarService?.showPopupFromNotification()
                        return
                    }
                    _ = try? await timerService?.advanceTimer()
                }
            },
            onFocusInactivity: { [weak self] delivery in
                guard let self else { return false }
                return await self.popups.presentInactivityPopup(for: delivery)
            },
            shouldSilenceAlert: { [weak windowService] kind in
                guard kind.hasPrefix("timer.") else { return false }
                return windowService?.breakScreensVisible == true
                    || windowService?.hardLimitPopupVisible == true
                    || windowService?.inactivityPopupVisible == true
            },
            breakDeferralSeconds: { [weak preferences, weak userActivityMonitor] in
                guard let preferences, let userActivityMonitor else { return nil }
                return BreakDeferralPolicy.seconds(
                    preferences: preferences.preferences,
                    recentlyActive: userActivityMonitor.isRecentlyActive
                        || userActivityMonitor.fallbackRecentlyActive()
                )
            }
        )

        self.windowService.configure(appState: self)
        self.statusBarService.configure(appState: self)
        self.settingsShortcutService.configure(appState: self)
        appUpdateService.configurePresentation(
            shouldDefer: { [weak self] in
                self?.isUpdatePresentationBlocked ?? false
            },
            willPresent: { [weak windowService] in
                windowService?.beginExternalWindowPresentation()
            },
            didFinish: { [weak windowService] in
                windowService?.endExternalWindowPresentation()
            }
        )
        daemonEventObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonEventReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CronaProtocolEvent else { return }
            Task { @MainActor [weak self] in
                self?.handleDaemonEvent(event)
            }
        }
        daemonConnectObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.alertSettingsService.refresh()
                await self.dayBoundarySettingsService.refresh()
                await self.coreSettingsService.refresh()
                await self.wellbeingService.refresh()
                await self.timerService.refresh()
                await self.contextService.refresh()
                await self.dailyFocusService.refresh(date: self.daemonConnection.currentDate)
                await self.habitsService.refresh(date: self.daemonConnection.currentDate)
                await self.popoverStatsService.refresh()
            }
        }
        bindChildChanges()
    }

    isolated deinit {
        if let daemonEventObserver {
            NotificationCenter.default.removeObserver(daemonEventObserver)
        }
        if let daemonConnectObserver {
            NotificationCenter.default.removeObserver(daemonConnectObserver)
        }
        presentationTimer?.invalidate()
    }

    var popoverModel: PopoverViewModel {
        PopoverViewModel(
            screen: popoverScreen,
            connectionState: daemonConnection.connectionState,
            timerSnapshot: timerService.snapshot,
            contextSnapshot: contextService.snapshot,
            lastErrorDescription: daemonConnection.lastErrorDescription
        )
    }

    var popoverScreen: PopoverScreen {
        if hasActiveFocusSession {
            return .active(
                ActiveTimerPopoverModel(
                    presentation: TimerPresentation.from(timerService.snapshot),
                    timerSnapshot: timerService.snapshot,
                    contextSnapshot: contextService.snapshot
                )
            )
        }
        if selectedPopoverTab == .stats {
            return .idle(IdleFocusPopoverModel(issues: [], date: ""))
        }
        if daemonConnection.connectionState == .error
            || daemonConnection.connectionState == .incompatible
        {
            return .error(
                message: daemonConnection.lastErrorDescription ?? "Unable to reach Crona.")
        }
        if daemonConnection.connectionState != .connected {
            return .disconnected
        }
        if selectedFocusIssue != nil || isAdhocStartSelected {
            let issue = selectedFocusIssue
            return .startConfig(
                FocusStartConfigModel(
                    issue: issue,
                    state: FocusStartConfigState.defaultState(
                        estimateMinutes: issue?.estimateMinutes,
                        workedSeconds: issue?.workedSeconds ?? 0
                    )
                )
            )
        }
        return .idle(
            IdleFocusPopoverModel(
                issues: dailyFocusService.snapshot.issues,
                date: dailyFocusService.snapshot.date
            )
        )
    }

    var todayIsAway: Bool { coreSettingsService.todayIsAway }

    func setAwayMode(_ enabled: Bool) {
        Task { await coreSettingsService.setAwayMode(enabled) }
    }

    var hasActiveFocusSession: Bool {
        timerService.snapshot.sessionID != nil
            && timerService.snapshot.state != "idle"
            && timerService.snapshot.state != "disconnected"
    }

    var isUpdatePresentationBlocked: Bool {
        hasActiveFocusSession
            || windowService.breakScreensVisible
            || windowService.hardLimitPopupVisible
            || endSession.isSheetPresented
            || issueActions.editor != nil
            || issueCreator.isPresented
    }

    func start() {
        notificationService.start()
        userActivityMonitor.start()
        launchAtLoginService.refresh()
        daemonConnection.start()
        smartPauseService.start()
        breakScreenService.start()
        appUpdateService.start()
        startPresentationTimer()
    }

    func stop() {
        presentationTimer?.invalidate()
        presentationTimer = nil
        notificationService.stop()
        userActivityMonitor.stop()
        inactivityPopupCountdownService.cancel()
        smartPauseService.stop()
        breakScreenService.stop()
        appUpdateService.stop()
        daemonConnection.stop()
    }

    private func startPresentationTimer() {
        guard presentationTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popups.reconcileTimedPresentation()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        presentationTimer = timer
    }

    func manualReconnect() {
        daemonConnection.manualReconnect()
    }

    func openIssueDetails(_ issue: DailyFocusIssue) {
        popoverDetailsRoute = .issueDetails(issueID: issue.id)
    }

    func openHabitDetails(_ habit: HabitRowModel) {
        popoverDetailsRoute = .habitDetails(habitID: habit.id)
    }

    func dismissDetails() {
        popoverDetailsRoute = nil
    }

    #if DEBUG
        var isDeveloperPreviewActive: Bool { developerPreviewKind != nil }

        func showDeveloperHardLimitPreview() {
            dismissDeveloperPreviews()
            developerPreviewKind = .hardLimit
            popups.showHardLimitPreview()
        }

        func showDeveloperInactivityPreview() {
            dismissDeveloperPreviews()
            developerPreviewKind = .inactivity
            popups.showInactivityPreview()
        }

        func showDeveloperWarningPreview() {
            dismissDeveloperPreviews()
            popups.showWarningPreview()
        }

        func showDeveloperSmartPauseResumePreview() {
            dismissDeveloperPreviews()
            popups.showSmartPauseResumePreview()
        }

        func showDeveloperBreakScreenPreview() {
            dismissDeveloperPreviews()
            developerPreviewKind = .breakScreen
            windowService.showDeveloperBreakScreen()
        }

        func dismissDeveloperPreviews() {
            popups.clearPreviewState()
            developerPreviewKind = nil
            endSession.clear()
            windowService.dismissDeveloperPreviews()
        }
    #endif

    func setSelectedPopoverTab(_ tab: PopoverTab) {
        guard !hasActiveFocusSession else {
            selectedPopoverTab = .now
            return
        }
        selectedPopoverTab = tab

        if tab == .wellbeing {
            Task { await wellbeingService.refresh() }
        }

    }

    func resetPopoverPresentation() {
        popoverDetailsRoute = nil
        selectedPopoverTab = .now
        if isStatsCalendarPresented {
            isStatsCalendarPresented = false
            popoverStatsService.endCalendar()
        }
    }

    func reconcileFunctionalDateOnPopoverOpen() async {
        guard daemonConnection.connectionState == .connected else { return }

        do {
            let health = try await daemonConnection.refreshHealth()
            guard let daemonDate = health.currentDate, !daemonDate.isEmpty else {
                logger.debug("Popup date reconciliation skipped: daemon date is empty")
                return
            }

            let storedDates = [
                dailyFocusService.snapshot.date,
                habitsService.snapshot.date,
                wellbeingService.snapshot.date,
                popoverStatsService.functionalDate,
            ]
            guard storedDates.contains(where: { $0 != daemonDate }) else {
                logger.debug("Popup date reconciliation not needed for \(daemonDate, privacy: .public)")
                return
            }

            logger.info("Reconciling popup date to daemon logical date \(daemonDate, privacy: .public)")
            await dailyFocusService.refresh(date: daemonDate)
            await habitsService.refresh(date: daemonDate)
            await wellbeingService.refresh(date: daemonDate)
            await popoverStatsService.reconcileToDate(daemonDate)
        } catch {
            logger.error("Popup date reconciliation failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func setSelectedSettingsDestination(_ destination: SettingsDestination) {
        selectedSettingsDestination = destination
    }

    func openSettings() {
        statusBarService.dismissPopup { [weak self] in
            guard let self, let settingsSceneAction = self.settingsSceneAction else {
                return
            }
            self.windowService.showSettings(openScene: settingsSceneAction)
        }
    }

    func presentPrimarySurfaceWhenNoWindowIsActive() {
        guard popups.hardLimitPopupPhase == nil, !windowService.hardLimitPopupVisible else { return }
        if preferences.preferences.showMenuBarItem {
            statusBarService.showPopupFromApplicationLaunch()
        } else {
            openSettings()
        }
    }

    func registerSettingsSceneAction(_ action: @escaping () -> Void) {
        settingsSceneAction = action
    }

    func openAbout() {
        setSelectedSettingsDestination(.about)
        openSettings()
    }

    func openUpdates() {
        setSelectedSettingsDestination(.about)
        openSettings()
    }

    func checkForAppUpdates() {
        statusBarService.dismissPopup(animated: false)
        appUpdateService.checkForUpdates()
    }

    func quitCrona() {
        statusBarService.dismissPopup(animated: false)
        NSApp.terminate(nil)
    }

    func openDocumentation() {
        openExternalURL("https://github.com/webxsid/crona/tree/main/docs")
    }

    func openGitHub() {
        openExternalURL("https://github.com/webxsid/crona")
    }

    func openSupport() {
        openExternalURL("https://github.com/webxsid/crona/discussions")
    }

    func openFeedbackAndRoadmap() {
        openExternalURL("https://crona.userjot.com/?cursor=1&order=top&limit=10")
    }

    private func openExternalURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    func requestStopCrona() {
        statusBarService.dismissPopup(animated: false)
        guard windowService.confirmStopCrona(hasActiveSession: hasActiveFocusSession) else {
            return
        }

        Task {
            do {
                try await daemonConnection.shutdownAndWait()
                NSApp.terminate(nil)
            } catch {
                logger.error(
                    "Failed to stop Crona: \(error.localizedDescription, privacy: .private)")
                windowService.showStopCronaError(error.localizedDescription)
            }
        }
    }

    func dismissMenuBarPopup() {
        statusBarService.dismissPopup()
    }

    func openTUI() {
        windowService.openTUI(using: preferences.preferences.tuiCommand)
    }

    func pauseTimer() {
        Task { _ = try? await timerService.pauseTimer() }
    }

    func resumeTimer() {
        Task { _ = try? await timerService.resumeTimer() }
    }

    func advanceTimer() {
        Task { _ = try? await timerService.advanceTimer() }
    }

    func endTimer() {
        endSession.begin(source: .menuPopover)
    }

    func endTimerFromHUD() {
        endSession.begin(source: .timerHUD)
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.endSession.presentationSource == .timerHUD else { return }
            self.windowService.setTimerHUDCommitPresented(true)
        }
    }

    func extendTimer() {
        extendTimer(by: nil)
    }

    func extendTimer(by additionalSeconds: Int?) {
        guard let request = buildExtendRequest(additionalSeconds: additionalSeconds) else {
            logger.error("Failed to build extend request: no positive extend value was provided")
            return
        }
        Task {
            do {
                _ = try await daemonConnection.withClient { try await $0.timerExtend(request) }
                await timerService.refresh()
            } catch {
                logger.error(
                    "Failed to extend timer: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func selectFocusIssue(_ issue: DailyFocusIssue) {
        selectedFocusIssue = issue
    }

    func beginAdhocStart() {
        guard !hasActiveFocusSession, !todayIsAway, daemonConnection.connectionState == .connected else { return }
        selectedFocusIssue = nil
        isAdhocStartSelected = true
        focusStartError = nil
    }

    func dismissStartConfig() {
        guard !isStartingFocus else { return }
        isAdhocStartSelected = false
        focusStartError = nil
        selectedFocusIssue = nil
    }

    func startSelectedFocusSession(using config: FocusStartConfigState) {
        guard !isStartingFocus, !hasActiveFocusSession, !todayIsAway,
              selectedFocusIssue != nil || isAdhocStartSelected else { return }
        let request = config.startRequest(for: selectedFocusIssue)
        isStartingFocus = true
        focusStartError = nil
        Task {
            defer { isStartingFocus = false }
            do {
                _ = try await daemonConnection.withClient { try await $0.timerStart(request) }
                await timerService.refresh()
                await contextService.refresh()
                await dailyFocusService.refresh()
                await habitsService.refresh()
                selectedFocusIssue = nil
                isAdhocStartSelected = false
            } catch {
                focusStartError = error.localizedDescription
            }
        }
    }

    func requestNotificationAuthorization() {
        Task { await notificationService.requestAuthorization() }
    }

    func sendTestNotification() {
        Task { await daemonConnection.sendTestNotification() }
    }

    func sendTestSound() {
        Task {
            do {
                _ = try await daemonConnection.withClient { client in
                    try await client.alertsTestSound()
                }
            } catch {
                daemonConnection.lastErrorDescription = error.localizedDescription
            }
        }
    }

    private func bindChildChanges() {
        preferences.$preferences
            .map(\.hideDockIconWhenNoWindowsOpen)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.windowService.refreshApplicationActivationPolicy()
            }
            .store(in: &cancellables)

        preferences.$preferences
            .map(\.settingsShortcut)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shortcut in
                self?.settingsShortcutService.update(shortcut: shortcut)
            }
            .store(in: &cancellables)

        dailyFocusService.$snapshot
            .map(\.issues)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] issues in
                self?.issueActionsService.synchronize(issues: issues)
            }
            .store(in: &cancellables)

        timerService.$snapshot
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                let isActive =
                    snapshot.sessionID != nil
                    && snapshot.state != "idle"
                    && snapshot.state != "disconnected"
                if isActive, self.selectedPopoverTab != .now {
                    self.selectedPopoverTab = .now
                }
                self.windowService.reconcileTimerHUD()
            }
            .store(in: &cancellables)

        [
            preferences.objectWillChange.eraseToAnyPublisher(),
            kernelDiscovery.objectWillChange.eraseToAnyPublisher(),
            notificationService.objectWillChange.eraseToAnyPublisher(),
            coreSettingsService.objectWillChange.eraseToAnyPublisher(),
            launchAtLoginService.objectWillChange.eraseToAnyPublisher(),
            daemonConnection.objectWillChange.eraseToAnyPublisher(),
            diagnosticsService.objectWillChange.eraseToAnyPublisher(),
            timerService.objectWillChange.eraseToAnyPublisher(),
            contextService.objectWillChange.eraseToAnyPublisher(),
            dailyFocusService.objectWillChange.eraseToAnyPublisher(),
            issueActionsService.objectWillChange.eraseToAnyPublisher(),
            issueCreationService.objectWillChange.eraseToAnyPublisher(),
            habitsService.objectWillChange.eraseToAnyPublisher(),
            wellbeingService.objectWillChange.eraseToAnyPublisher(),
            popoverStatsService.objectWillChange.eraseToAnyPublisher(),
            breakScreenService.objectWillChange.eraseToAnyPublisher(),
            appUpdateService.objectWillChange.eraseToAnyPublisher(),
        ]
        .forEach { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.statusBarService.updateStatusItem()
                    self?.endSession.reconcile()
                    self?.popups.reconcile()
                    self?.windowService.reconcileTimerHUD()
                }
                .store(in: &cancellables)
        }

        // Only services read by CompanionAppState's own view-facing properties are forwarded;
        // views observe every other service directly.
        [
            preferences.objectWillChange.eraseToAnyPublisher(),
            coreSettingsService.objectWillChange.eraseToAnyPublisher(),
            daemonConnection.objectWillChange.eraseToAnyPublisher(),
            timerService.objectWillChange.eraseToAnyPublisher(),
            contextService.objectWillChange.eraseToAnyPublisher(),
            dailyFocusService.objectWillChange.eraseToAnyPublisher(),
        ]
        .forEach { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }

    private func handleDaemonEvent(_ event: CronaProtocolEvent) {
        switch event.type {
        case "session.started", "session.stopped", "session.ended":
            issueActionsService.refreshTransitionsAfterSessionChange()
            if event.type == "session.ended" {
                guard let sessionID = event.sessionID else { return }
                finalizeEndSessionIfNeeded(for: sessionID)
            }
        case "day.start":
            handleDayStart(event)
        case "timer.hard_limit_reached":
            popups.handleHardLimitReached(sessionID: event.sessionID)
        case "timer.extended":
            popups.handleTimerExtended(sessionID: event.sessionID)
        default:
            break
        }
    }

    private func handleDayStart(_ event: CronaProtocolEvent) {
        guard let payload = try? event.decodePayload(CronaDayBoundaryEventPayload.self),
            !payload.logicalDate.isEmpty
        else {
            logger.error("Ignoring malformed day.start event")
            return
        }

        let previousDate = daemonConnection.currentDate
        guard daemonConnection.applyDayBoundary(payload) else { return }
        let date = payload.logicalDate
        Task { @MainActor [weak self] in
            guard let self else { return }
            await dailyFocusService.refresh(date: date)
            await habitsService.refresh(date: date)
            await wellbeingService.refresh()
            await coreSettingsService.refresh()
            await popoverStatsService.handleDayStart(date: date, previousDate: previousDate)
            statusBarService.updateStatusItem()
        }
    }

    private func buildExtendRequest(additionalSeconds: Int?) -> CronaTimerExtendRequest? {
        Self.buildQuickExtendRequest(
            snapshot: timerService.snapshot, additionalSeconds: additionalSeconds)
    }

    static func buildQuickExtendRequest(snapshot: TimerSnapshot, additionalSeconds: Int?)
        -> CronaTimerExtendRequest?
    {
        guard let additionalSeconds, additionalSeconds > 0 else {
            return nil
        }

        return CronaTimerExtendRequest(
            additionalSeconds: additionalSeconds,
            additionalSessions: 0,
            hardLimitTotalSeconds: nil,
            hardLimitWorkSeconds: nil,
            hardLimitBreakSeconds: nil,
            hardLimitLongBreakSeconds: nil,
            hardLimitCyclesBeforeLongBreak: nil
        )
    }

    private func finalizeEndSessionIfNeeded(for sessionID: String) {
        guard !endSession.finalizeIfPending(sessionID: sessionID) else { return }
        popups.finalizePopups(forSessionID: sessionID)
    }

}

enum PopoverDetailRoute: Equatable {
    case issueDetails(issueID: Int64)
    case habitDetails(habitID: Int64)

    var title: String {
        switch self {
        case .issueDetails: return "Issue Details"
        case .habitDetails: return "Habit Details"
        }
    }
}
