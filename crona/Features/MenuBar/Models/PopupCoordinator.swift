import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class PopupCoordinator: ObservableObject {
    private let logger = Logger(subsystem: "com.crona.macos", category: "app")

    @Published var hardLimitPopupPhase: HardLimitPopupPhase?
    @Published private(set) var hardLimitPopupSessionID: String?
    @Published var hardLimitPopupExtendChoice = HardLimitExtendChoice.defaultValue
    @Published var hardLimitPopupErrorMessage: String?
    @Published var isSubmittingHardLimitAction = false
    @Published var hardLimitPopupSuccessModel: HardLimitPopupSuccessModel?
    @Published var hardLimitWarningIndicatorModel: HardLimitWarningIndicatorModel?
    @Published var isHardLimitPopupAnimatingIn = false
    @Published var inactivityPopupPhase: InactivityPopupPhase?
    @Published var inactivityPopupDelivery: CronaAlertDelivery?
    @Published private(set) var inactivityPopupSessionID: String?
    @Published var isHardLimitWarningIndicatorAnimatingIn = false
    @Published var smartPauseResumeNotice: SmartPauseResumeNotice?

    #if DEBUG
        var developerPreviewKind: () -> DeveloperPreviewKind? = { nil }
        var dismissDeveloperPreviews: () -> Void = {}
    #endif

    private let daemonConnection: DaemonConnectionService
    private let timerService: TimerService
    private let contextService: ContextService
    private let preferences: PreferencesService
    private let windowService: WindowService
    private let endSession: EndSessionModel
    private let hardLimitCountdownService: HardLimitCountdownService
    private let inactivityPopupCountdownService: HardLimitCountdownService
    private var hardLimitPopupDismissTask: Task<Void, Never>?
    private var smartPauseResumeNoticeDismissTask: Task<Void, Never>?
    private var lastWarningIndicatorKey: String?

    init(
        daemonConnection: DaemonConnectionService,
        timerService: TimerService,
        contextService: ContextService,
        preferences: PreferencesService,
        windowService: WindowService,
        endSession: EndSessionModel,
        hardLimitCountdownService: HardLimitCountdownService,
        inactivityPopupCountdownService: HardLimitCountdownService
    ) {
        self.daemonConnection = daemonConnection
        self.timerService = timerService
        self.contextService = contextService
        self.preferences = preferences
        self.windowService = windowService
        self.endSession = endSession
        self.hardLimitCountdownService = hardLimitCountdownService
        self.inactivityPopupCountdownService = inactivityPopupCountdownService
    }

    isolated deinit {
        hardLimitPopupDismissTask?.cancel()
        smartPauseResumeNoticeDismissTask?.cancel()
    }

    private var isPreviewing: (hardLimit: Bool, inactivity: Bool) {
        #if DEBUG
            let kind = developerPreviewKind()
            return (kind == .hardLimit, kind == .inactivity)
        #else
            return (false, false)
        #endif
    }

    // MARK: Hard-limit popup

    func handleHardLimitReached(sessionID: String?) {
        logger.debug(
            "Handling hard limit popup for session: \(sessionID ?? "nil", privacy: .private(mask: .hash))"
        )
        Task { [self] in
            await timerService.refresh()
            await contextService.refresh()
            await MainActor.run {
                guard preferences.preferences.showHardLimitActionPopups else { return }
                guard timerService.snapshot.sessionID != nil else { return }
                guard timerService.snapshot.hardLimitActive, timerService.snapshot.hardLimitExpired
                else { return }

                finalizeHardLimitWarningIndicator()
                hardLimitPopupDismissTask?.cancel()
                hardLimitPopupDismissTask = nil
                hardLimitPopupSessionID = timerService.snapshot.sessionID
                hardLimitPopupPhase = .decision
                hardLimitPopupExtendChoice = defaultExtendChoice(for: timerService.snapshot)
                hardLimitPopupErrorMessage = nil
                hardLimitPopupSuccessModel = nil
                isSubmittingHardLimitAction = false
                isHardLimitPopupAnimatingIn = false
                startHardLimitDecisionCountdown()
                windowService.showHardLimitPopup()
                DispatchQueue.main.async {
                    self.isHardLimitPopupAnimatingIn = true
                }
            }
        }
    }

    func handleTimerExtended(sessionID eventSessionID: String?) {
        guard let sessionID = hardLimitPopupSessionID,
            sessionID == eventSessionID || eventSessionID == nil
        else { return }
        Task {
            await timerService.refresh()
            await contextService.refresh()
            await MainActor.run {
                presentExtendSuccess()
            }
        }
    }

    func chooseHardLimitEnd() {
        if isPreviewing.hardLimit {
            hardLimitPopupPhase = .endSession
            endSession.setPreviewPending(source: .hardLimitPopup)
            windowService.updateHardLimitPopup()
            return
        }
        hardLimitCountdownService.cancel()
        endSession.begin(source: .hardLimitPopup)
        guard endSession.pendingSessionID != nil else { return }
        hardLimitPopupErrorMessage = nil
        hardLimitPopupPhase = .endSession
        windowService.updateHardLimitPopup()
        endSession.requestFocus()
    }

    func handleHardLimitPopupClose() {
        guard !endSession.isSubmitting, !isSubmittingHardLimitAction else { return }
        chooseHardLimitEnd()
    }

    func chooseHardLimitExtend() {
        if isPreviewing.hardLimit {
            hardLimitPopupPhase = .extend
            hardLimitPopupExtendChoice = .minutes5
            windowService.updateHardLimitPopup()
            return
        }
        hardLimitCountdownService.cancel()
        guard let sessionID = timerService.snapshot.sessionID else { return }
        hardLimitPopupSessionID = sessionID
        hardLimitPopupErrorMessage = nil
        hardLimitPopupExtendChoice = defaultExtendChoice(for: timerService.snapshot)
        hardLimitPopupPhase = .extend
        windowService.updateHardLimitPopup()
    }

    func confirmHardLimitExtend() {
        if isPreviewing.hardLimit {
            hardLimitPopupPhase = .success
            hardLimitPopupSuccessModel = HardLimitPopupSuccessModel(
                remainingTimeText: "30:00",
                endTimeText: TimerEndTimeFormatter.string(
                    from: Date().addingTimeInterval(1_800))
            )
            windowService.updateHardLimitPopup()
            return
        }
        guard let sessionID = hardLimitPopupSessionID ?? timerService.snapshot.sessionID else {
            return
        }
        guard sessionID == timerService.snapshot.sessionID else {
            hardLimitPopupErrorMessage = "The active session changed. Refresh and try again."
            return
        }

        let request: CronaTimerExtendRequest?
        switch TimerPresentation.from(timerService.snapshot).mode {
        case .pomodoro:
            request = buildPomodoroExtendRequest(choice: hardLimitPopupExtendChoice)
        case .stopwatch, .timer:
            request = CompanionAppState.buildQuickExtendRequest(
                snapshot: timerService.snapshot,
                additionalSeconds: hardLimitPopupExtendChoice.secondsValue)
        }

        guard let request else {
            hardLimitPopupErrorMessage = "No extend option is available."
            return
        }

        isSubmittingHardLimitAction = true
        hardLimitPopupErrorMessage = nil

        Task {
            do {
                _ = try await daemonConnection.withClient { try await $0.timerExtend(request) }
                await timerService.refresh()
                await contextService.refresh()
                await MainActor.run {
                    self.presentExtendSuccess()
                }
            } catch {
                logger.error(
                    "Failed to extend timer from popup: \(error.localizedDescription, privacy: .private)"
                )
                await MainActor.run {
                    self.isSubmittingHardLimitAction = false
                    self.hardLimitPopupErrorMessage = error.localizedDescription
                }
            }
        }
    }

    var hardLimitExtensionEndDate: Date? {
        if isPreviewing.hardLimit {
            return Date().addingTimeInterval(1_800)
        }
        let request: CronaTimerExtendRequest?
        switch TimerPresentation.from(timerService.snapshot).mode {
        case .pomodoro:
            request = buildPomodoroExtendRequest(choice: hardLimitPopupExtendChoice)
        case .stopwatch, .timer:
            request = CompanionAppState.buildQuickExtendRequest(
                snapshot: timerService.snapshot,
                additionalSeconds: hardLimitPopupExtendChoice.secondsValue
            )
        }

        guard let request else { return nil }
        return TimerEndProjection.extensionEndDate(
            snapshot: timerService.snapshot,
            request: request
        )
    }

    func returnToHardLimitDecision() {
        guard !endSession.isSubmitting, !isSubmittingHardLimitAction else { return }
        if isPreviewing.hardLimit {
            endSession.clear(preserveDraft: timerService.snapshot.adhoc)
            hardLimitPopupErrorMessage = nil
            hardLimitPopupPhase = .decision
            windowService.updateHardLimitPopup()
            return
        }
        endSession.clear(preserveDraft: timerService.snapshot.adhoc)
        hardLimitPopupErrorMessage = nil
        hardLimitPopupPhase = .decision
        startHardLimitDecisionCountdown()
        windowService.updateHardLimitPopup()
    }

    // MARK: Inactivity popup

    func presentInactivityPopup(for delivery: CronaAlertDelivery) async -> Bool {
        guard preferences.preferences.showInactivityActionPopups else { return false }

        await timerService.refresh()
        await contextService.refresh()

        guard preferences.preferences.showInactivityActionPopups else { return false }
        guard timerService.snapshot.sessionID != nil else { return false }
        guard timerService.snapshot.state == "running" else { return false }
        guard !timerService.snapshot.hardLimitExpired else { return false }

        inactivityPopupCountdownService.cancel()
        inactivityPopupDelivery = delivery
        inactivityPopupSessionID = timerService.snapshot.sessionID
        inactivityPopupPhase = .decision
        startInactivityPopupCountdown()
        windowService.showInactivityPopup()

        return true
    }

    func chooseInactivityPopupEnd() {
        if isPreviewing.inactivity {
            inactivityPopupPhase = .endSession
            endSession.setPreviewPending(source: .inactivityPopup)
            windowService.updateInactivityPopup()
            return
        }
        inactivityPopupCountdownService.cancel()
        endSession.begin(source: .inactivityPopup)
        guard endSession.pendingSessionID != nil else { return }
        inactivityPopupPhase = .endSession
        windowService.updateInactivityPopup()
        endSession.requestFocus()
    }

    func dismissInactivityPopup() {
        #if DEBUG
            if isPreviewing.inactivity {
                dismissDeveloperPreviews()
                return
            }
        #endif
        finalizeInactivityPopup()
    }

    func returnToInactivityDecision() {
        guard !endSession.isSubmitting else { return }
        if isPreviewing.inactivity {
            endSession.clear(preserveDraft: timerService.snapshot.adhoc)
            inactivityPopupPhase = .decision
            windowService.updateInactivityPopup()
            return
        }
        endSession.clear(preserveDraft: timerService.snapshot.adhoc)
        inactivityPopupPhase = .decision
        startInactivityPopupCountdown()
        windowService.updateInactivityPopup()
    }

    // MARK: Smart-pause resume notice

    func presentSmartPauseResumeNotice(for snapshot: TimerSnapshot) {
        guard let sessionID = snapshot.sessionID else { return }

        smartPauseResumeNoticeDismissTask?.cancel()
        smartPauseResumeNotice = SmartPauseResumeNotice(
            sessionID: sessionID,
            resumedAt: Date()
        )
        windowService.showSmartPauseResumeNotice()

        smartPauseResumeNoticeDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismissSmartPauseResumeNotice()
        }
    }

    func dismissSmartPauseResumeNotice() {
        smartPauseResumeNoticeDismissTask?.cancel()
        smartPauseResumeNoticeDismissTask = nil
        windowService.closeSmartPauseResumeNotice { [weak self] in
            self?.smartPauseResumeNotice = nil
        }
    }

    // MARK: Lifecycle

    /// Closes the popups bound to `sessionID`, or every open popup when `sessionID` is nil.
    func finalizePopups(forSessionID sessionID: String?) {
        if let sessionID {
            if hardLimitPopupSessionID == sessionID {
                finalizeHardLimitPopup()
            }
            if inactivityPopupSessionID == sessionID {
                finalizeInactivityPopup()
            }
        } else {
            if hardLimitPopupSessionID != nil {
                finalizeHardLimitPopup()
            }
            if inactivityPopupSessionID != nil {
                finalizeInactivityPopup()
            }
        }
    }

    func reconcile() {
        reconcileHardLimitPopupPresentation()
        reconcileHardLimitWarningIndicatorPresentation()
        reconcileInactivityPopupPresentation()
    }

    func reconcileTimedPresentation() {
        reconcileHardLimitWarningIndicatorPresentation()
        reconcileInactivityPopupPresentation()
    }

    private func reconcileHardLimitPopupPresentation() {
        guard let phase = hardLimitPopupPhase else { return }

        guard daemonConnection.connectionState == .connected else {
            finalizeHardLimitPopup()
            return
        }

        guard let sessionID = hardLimitPopupSessionID ?? timerService.snapshot.sessionID else {
            finalizeHardLimitPopup()
            return
        }

        if timerService.snapshot.sessionID != sessionID, phase != .success {
            finalizeHardLimitPopup()
            return
        }

        windowService.updateHardLimitPopup()
    }

    private func reconcileInactivityPopupPresentation() {
        guard inactivityPopupPhase != nil else { return }

        if isPreviewing.inactivity {
            windowService.updateInactivityPopup()
            return
        }

        guard preferences.preferences.showInactivityActionPopups else {
            finalizeInactivityPopup()
            return
        }

        guard daemonConnection.connectionState == .connected else {
            finalizeInactivityPopup()
            return
        }

        guard let sessionID = inactivityPopupSessionID else {
            finalizeInactivityPopup()
            return
        }

        guard timerService.snapshot.sessionID == sessionID else {
            finalizeInactivityPopup()
            return
        }

        windowService.updateInactivityPopup()
    }

    private func reconcileHardLimitWarningIndicatorPresentation() {
        guard preferences.preferences.showHardLimitWarningIndicator else {
            finalizeHardLimitWarningIndicator()
            return
        }

        guard daemonConnection.connectionState == .connected else {
            finalizeHardLimitWarningIndicator()
            return
        }

        let snapshot = timerService.snapshot
        guard snapshot.sessionID != nil, snapshot.state == "running", snapshot.hardLimitActive,
            !snapshot.hardLimitExpired
        else {
            finalizeHardLimitWarningIndicator()
            return
        }

        guard let model = buildHardLimitWarningIndicatorModel(snapshot: snapshot) else {
            finalizeHardLimitWarningIndicator()
            return
        }

        if lastWarningIndicatorKey != model.id {
            lastWarningIndicatorKey = model.id
        }
        if hardLimitWarningIndicatorModel != model {
            hardLimitWarningIndicatorModel = model
        }
        if !windowService.hardLimitWarningIndicatorVisible {
            isHardLimitWarningIndicatorAnimatingIn = false
            windowService.showHardLimitWarningIndicator()
            DispatchQueue.main.async {
                self.isHardLimitWarningIndicatorAnimatingIn = true
            }
        }
    }

    private func presentExtendSuccess() {
        hardLimitCountdownService.cancel()
        let presentation = TimerPresentation.from(timerService.snapshot)
        let timeFormatter = MenuBarTextFormatter.formatClock(
            seconds: presentation.displaySeconds
        )
        let endTimeText: String
        if let endDate = TimerEndProjection.activeEndDate(snapshot: timerService.snapshot) {
            endTimeText = TimerEndTimeFormatter.string(from: endDate)
        } else {
            endTimeText = "Now"
        }

        hardLimitPopupPhase = .success
        hardLimitPopupSuccessModel = HardLimitPopupSuccessModel(
            remainingTimeText: timeFormatter,
            endTimeText: endTimeText
        )
        hardLimitPopupErrorMessage = nil
        isSubmittingHardLimitAction = false
        windowService.updateHardLimitPopup()

        hardLimitPopupDismissTask?.cancel()
        hardLimitPopupDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            self?.finalizeHardLimitPopup()
        }
    }

    private func finalizeHardLimitPopup() {
        hardLimitCountdownService.cancel()
        hardLimitPopupDismissTask?.cancel()
        hardLimitPopupDismissTask = nil
        isHardLimitPopupAnimatingIn = false
        windowService.closeHardLimitPopup { [weak self] in
            guard let self else { return }
            self.hardLimitPopupPhase = nil
            self.hardLimitPopupSessionID = nil
            self.hardLimitPopupExtendChoice = .defaultValue
            self.hardLimitPopupErrorMessage = nil
            self.hardLimitPopupSuccessModel = nil
            self.isSubmittingHardLimitAction = false
            self.windowService.reconcileTimerHUD()
        }
    }

    private func finalizeInactivityPopup() {
        inactivityPopupCountdownService.cancel()
        windowService.closeInactivityPopup { [weak self] in
            guard let self else { return }
            self.inactivityPopupPhase = nil
            self.inactivityPopupDelivery = nil
            self.inactivityPopupSessionID = nil
            if self.endSession.presentationSource == .inactivityPopup {
                self.endSession.clear()
            }
        }
    }

    private func finalizeHardLimitWarningIndicator() {
        guard
            hardLimitWarningIndicatorModel != nil
                || windowService.hardLimitWarningIndicatorVisible
        else {
            return
        }
        isHardLimitWarningIndicatorAnimatingIn = false
        windowService.closeHardLimitWarningIndicator { [weak self] in
            guard let self else { return }
            self.hardLimitWarningIndicatorModel = nil
            self.lastWarningIndicatorKey = nil
        }
    }

    private func startHardLimitDecisionCountdown() {
        hardLimitCountdownService.start { [weak self] in
            guard let self, self.hardLimitPopupPhase == .decision else { return }
            self.chooseHardLimitEnd()
        }
    }

    private func startInactivityPopupCountdown() {
        inactivityPopupCountdownService.start(
            duration: InactivityPopupConfiguration.autoDismissDuration
        ) { [weak self] in
            guard let self, self.inactivityPopupPhase == .decision else { return }
            self.finalizeInactivityPopup()
        }
    }

    private func defaultExtendChoice(for snapshot: TimerSnapshot) -> HardLimitExtendChoice {
        switch TimerPresentation.from(snapshot).mode {
        case .pomodoro:
            return .session1
        case .stopwatch, .timer:
            return .minutes5
        }
    }

    private func buildPomodoroExtendRequest(choice: HardLimitExtendChoice)
        -> CronaTimerExtendRequest?
    {
        guard let sessions = choice.sessionValue, sessions > 0 else { return nil }
        return CronaTimerExtendRequest(
            additionalSeconds: 0,
            additionalSessions: sessions,
            hardLimitTotalSeconds: max(1, timerService.snapshot.hardLimitTotalSeconds),
            hardLimitWorkSeconds: max(1, timerService.snapshot.hardLimitWorkSeconds),
            hardLimitBreakSeconds: max(0, timerService.snapshot.hardLimitBreakSeconds),
            hardLimitLongBreakSeconds: max(0, timerService.snapshot.hardLimitLongBreakSeconds),
            hardLimitCyclesBeforeLongBreak: max(
                0, timerService.snapshot.hardLimitCyclesBeforeLongBreak)
        )
    }

    private func buildHardLimitWarningIndicatorModel(snapshot: TimerSnapshot)
        -> HardLimitWarningIndicatorModel?
    {
        let leadSeconds = CompanionPreferences.normalizedHardLimitWarningLeadSeconds(
            preferences.preferences.hardLimitWarningLeadSeconds
        )
        let presentation = TimerPresentation.from(snapshot)
        let remainingSeconds = max(0, presentation.displaySeconds)
        guard remainingSeconds > 0, remainingSeconds <= leadSeconds else { return nil }

        let sessionID = snapshot.sessionID ?? "unknown"
        if presentation.mode == .pomodoro,
            let currentSegment = TimerSegmentKind(rawValue: snapshot.segmentType),
            let nextSegment = TimerSegmentKind(rawValue: snapshot.nextSegmentType),
            currentSegment != nextSegment
        {
            let kind: HardLimitWarningKind
            let title: String

            if currentSegment.isBreak, nextSegment == .work {
                kind = .resume
                title = "Focus Resumes"
            } else if currentSegment == .work, nextSegment.isBreak {
                kind = .breakStart
                title = "Break Starting"
            } else {
                return nil
            }

            let id =
                "\(sessionID):\(kind.rawValue):\(snapshot.segmentType ?? "unknown"):\(snapshot.nextSegmentType ?? "unknown")"
            return HardLimitWarningIndicatorModel(
                id: id,
                kind: kind,
                title: title,
                remainingText: String(format: "%02d", remainingSeconds)
            )
        }

        let id = "\(sessionID):expiry:\(snapshot.segmentType ?? "unknown")"
        return HardLimitWarningIndicatorModel(
            id: id,
            kind: .expiry,
            title: "Session Ending",
            remainingText: String(format: "%02d", remainingSeconds)
        )
    }

    // MARK: Developer previews

    #if DEBUG
        func showHardLimitPreview() {
            hardLimitPopupSessionID = "developer-preview"
            hardLimitPopupPhase = .decision
            hardLimitPopupExtendChoice = .minutes5
            hardLimitPopupErrorMessage = nil
            hardLimitPopupSuccessModel = nil
            isHardLimitPopupAnimatingIn = true
            windowService.showHardLimitPopup()
        }

        func showInactivityPreview() {
            inactivityPopupSessionID = "developer-preview"
            inactivityPopupPhase = .decision
            inactivityPopupDelivery = nil
            windowService.showInactivityPopup()
        }

        func showWarningPreview() {
            hardLimitWarningIndicatorModel = HardLimitWarningIndicatorModel(
                id: "developer-warning",
                kind: .expiry,
                title: "Session Ending",
                remainingText: "10"
            )
            isHardLimitWarningIndicatorAnimatingIn = false
            windowService.showHardLimitWarningIndicator()
            DispatchQueue.main.async {
                self.isHardLimitWarningIndicatorAnimatingIn = true
            }
        }

        func showSmartPauseResumePreview() {
            smartPauseResumeNotice = SmartPauseResumeNotice(
                sessionID: "developer-preview",
                resumedAt: Date()
            )
            windowService.showSmartPauseResumeNotice()
        }

        func clearPreviewState() {
            hardLimitCountdownService.cancel()
            inactivityPopupCountdownService.cancel()
            hardLimitPopupPhase = nil
            hardLimitPopupSessionID = nil
            hardLimitPopupSuccessModel = nil
            inactivityPopupPhase = nil
            inactivityPopupSessionID = nil
            inactivityPopupDelivery = nil
            hardLimitWarningIndicatorModel = nil
            smartPauseResumeNotice = nil
        }
    #endif
}

enum HardLimitPopupPhase: Equatable {
    case decision
    case endSession
    case extend
    case success
}

enum InactivityPopupPhase: Equatable {
    case decision
    case endSession
}

enum InactivityPopupConfiguration {
    static let autoDismissDuration: TimeInterval = 60
}

enum HardLimitExtendChoice: String, CaseIterable, Identifiable, Equatable {
    case minutes1
    case minutes5
    case minutes15
    case session1
    case session2

    static let defaultValue: HardLimitExtendChoice = .minutes5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes1: return "1 min — Quick wrap-up"
        case .minutes5: return "5 min — Finish the current task"
        case .minutes15: return "15 min — Continue the focus block"
        case .session1: return "1 session — Continue the current cadence"
        case .session2: return "2 sessions — Make a deeper pass"
        }
    }

    var secondsValue: Int? {
        switch self {
        case .minutes1: return 60
        case .minutes5: return 300
        case .minutes15: return 900
        case .session1, .session2: return nil
        }
    }

    var sessionValue: Int? {
        switch self {
        case .session1: return 1
        case .session2: return 2
        case .minutes1, .minutes5, .minutes15: return nil
        }
    }
}

struct HardLimitPopupSuccessModel: Equatable {
    let remainingTimeText: String
    let endTimeText: String
}

enum HardLimitWarningKind: String, Equatable {
    case expiry
    case breakStart
    case resume

    var symbolName: String {
        switch self {
        case .expiry:
            return "hourglass.circle.fill"
        case .breakStart:
            return "cup.and.saucer.fill"
        case .resume:
            return "bolt.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .expiry:
            return .systemOrange
        case .breakStart:
            return .systemPink
        case .resume:
            return .systemYellow
        }
    }
}

struct HardLimitWarningIndicatorModel: Equatable {
    let id: String
    let kind: HardLimitWarningKind
    let title: String
    let remainingText: String
}
