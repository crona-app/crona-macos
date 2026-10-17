import Combine
import Foundation
import OSLog

@MainActor
final class EndSessionModel: ObservableObject {
    private let logger = Logger(subsystem: "com.crona.macos", category: "app")

    @Published var isSheetPresented = false
    @Published var commitMessage = ""
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published var adhocAttribution = AdhocAttributionState()
    @Published private(set) var pendingSessionID: String?
    @Published private(set) var presentationSource: EndSessionPresentationSource?
    @Published private(set) var focusRequest = 0

    private let daemonConnection: DaemonConnectionService
    private let timerService: TimerService
    private let contextService: ContextService
    private let dailyFocusService: DailyFocusService
    private let habitsService: HabitsService
    private let popoverStatsService: PopoverStatsService
    private let issueCreationService: IssueCreationService
    private let windowService: WindowService
    private let handlesConfirmInPreview: () -> Bool
    private let onFinalized: () -> Void
    private var draftSessionID: String?
    private var fallbackTask: Task<Void, Never>?

    init(
        daemonConnection: DaemonConnectionService,
        timerService: TimerService,
        contextService: ContextService,
        dailyFocusService: DailyFocusService,
        habitsService: HabitsService,
        popoverStatsService: PopoverStatsService,
        issueCreationService: IssueCreationService,
        windowService: WindowService,
        handlesConfirmInPreview: @escaping () -> Bool,
        onFinalized: @escaping () -> Void
    ) {
        self.daemonConnection = daemonConnection
        self.timerService = timerService
        self.contextService = contextService
        self.dailyFocusService = dailyFocusService
        self.habitsService = habitsService
        self.popoverStatsService = popoverStatsService
        self.issueCreationService = issueCreationService
        self.windowService = windowService
        self.handlesConfirmInPreview = handlesConfirmInPreview
        self.onFinalized = onFinalized
    }

    isolated deinit {
        fallbackTask?.cancel()
    }

    var adhocCompletionHeight: CGFloat {
        (adhocAttribution.resolution == .create && adhocAttribution.createdIssue != nil
            ? AdhocCompletionLayout.height(for: .keep)
            : AdhocCompletionLayout.height(for: adhocAttribution.resolution))
            + (adhocAttribution.loadError != nil || errorMessage != nil ? 48 : 0)
    }

    var actionTitle: String {
        guard timerService.snapshot.adhoc else { return "End Session" }
        switch adhocAttribution.resolution {
        case .attach: return "Attach & Finish"
        case .create: return adhocAttribution.createdIssue == nil ? "Create & Finish" : "Retry & Finish"
        case .keep: return "Keep Ad Hoc & Finish"
        case nil: return "End Session"
        }
    }

    var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard timerService.snapshot.adhoc else { return true }
        guard let resolution = adhocAttribution.resolution else { return false }
        return resolution != .create || adhocAttribution.createdIssue != nil || adhocAttribution.estimateMinutes >= 0
    }

    var adhocElapsedSeconds: Int {
        guard let start = timerService.snapshot.sessionStartTime else { return max(0, timerService.snapshot.elapsedSeconds) }
        return max(0, Int(Date().timeIntervalSince(start)))
    }

    func begin(source: EndSessionPresentationSource) {
        guard let sessionID = timerService.snapshot.sessionID else {
            logger.error("Cannot present end session flow without an active session")
            return
        }
        logger.debug(
            "Presenting end session flow from \(String(describing: source), privacy: .public)")
        if draftSessionID != sessionID {
            adhocAttribution = .initial(
                elapsedSeconds: adhocElapsedSeconds,
                date: daemonConnection.currentDate,
                streamID: contextService.snapshot.streamID
            )
            commitMessage = ""
        }
        draftSessionID = sessionID
        pendingSessionID = sessionID
        presentationSource = source
        errorMessage = nil
        isSheetPresented = source == .menuPopover
        requestFocus()
    }

    func cancel() {
        guard !isSubmitting else { return }
        let wasPresentedInHUD = presentationSource == .timerHUD
        fallbackTask?.cancel()
        fallbackTask = nil
        isSheetPresented = false
        clear(preserveDraft: timerService.snapshot.adhoc)
        if wasPresentedInHUD {
            windowService.setTimerHUDCommitPresented(false)
        }
    }

    func confirm() {
        guard !isSubmitting else { return }
        let trimmedMessage = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            errorMessage = timerService.snapshot.adhoc ? "A session summary is required." : "A commit message is required."
            requestFocus()
            return
        }
        if handlesConfirmInPreview() { return }
        guard let sessionID = pendingSessionID, sessionID == timerService.snapshot.sessionID
        else {
            errorMessage = "The active session changed. Refresh and try again."
            return
        }

        var request = CronaEndSessionRequest(commitMessage: trimmedMessage)
        var creation: CronaCreateIssueRequest?
        if timerService.snapshot.adhoc {
            guard let resolution = adhocAttribution.resolution else {
                errorMessage = "Choose how to save this session."
                return
            }
            request.adhocResolution = resolution
            switch resolution {
            case .keep: break
            case .attach:
                guard let id = adhocAttribution.selectedIssueID,
                      let issue = adhocAttribution.issues.first(where: { $0.id == id }),
                      ["planned", "ready", "in_progress"].contains(issue.status) else {
                    errorMessage = "Choose an eligible issue."
                    return
                }
                request.issueID = id
            case .create:
                if let issue = adhocAttribution.createdIssue {
                    request.adhocResolution = .attach
                    request.issueID = issue.id
                } else {
                    guard let destination = issueCreationService.destinations.first(where: { $0.id == adhocAttribution.destinationID }),
                          !adhocAttribution.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        errorMessage = "Choose a destination and enter an issue title."
                        return
                    }
                    let date = adhocAttribution.date.trimmingCharacters(in: .whitespacesAndNewlines)
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "yyyy-MM-dd"
                    formatter.isLenient = false
                    guard date.isEmpty || (formatter.date(from: date).map { formatter.string(from: $0) == date } ?? false),
                          adhocAttribution.estimateMinutes >= 0 else {
                        errorMessage = "Enter a valid date and nonnegative estimate."
                        return
                    }
                    creation = CronaCreateIssueRequest(
                        streamID: destination.streamID,
                        title: adhocAttribution.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: optionalTrimmed(adhocAttribution.description),
                        estimateMinutes: adhocAttribution.estimateMinutes > 0 ? adhocAttribution.estimateMinutes : nil,
                        todoForDate: date.isEmpty ? nil : date
                    )
                }
            }
        }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                if let creation {
                    let issue = try await daemonConnection.withClient { try await $0.createIssue(creation) }
                    guard pendingSessionID == sessionID, timerService.snapshot.sessionID == sessionID else {
                        throw NSError(domain: "Crona", code: 1, userInfo: [NSLocalizedDescriptionKey: "The active session changed. The issue was created, but the session was not attached."])
                    }
                    adhocAttribution.createdIssue = issue
                    request.adhocResolution = .attach
                    request.issueID = issue.id
                }
                if let created = adhocAttribution.createdIssue, created.status == "backlog" {
                    let issues = try await daemonConnection.withClient { try await $0.listAllIssues() }
                    guard let latest = issues.first(where: { $0.id == created.id }) else {
                        throw NSError(domain: "Crona", code: 1, userInfo: [NSLocalizedDescriptionKey: "The created issue is no longer available."])
                    }
                    let prepared = latest.status == "backlog"
                        ? try await daemonConnection.withClient { try await $0.changeIssueStatus(issueID: latest.id, status: .ready, note: nil) }
                        : latest
                    guard pendingSessionID == sessionID, timerService.snapshot.sessionID == sessionID else {
                        throw NSError(domain: "Crona", code: 1, userInfo: [NSLocalizedDescriptionKey: "The active session changed. The issue was created, but the session was not attached."])
                    }
                    adhocAttribution.createdIssue = prepared
                }
                let requestToEnd = request
                _ = try await daemonConnection.withClient { try await $0.timerEnd(requestToEnd) }
                await dailyFocusService.refresh()
                await contextService.refresh()
                await popoverStatsService.refresh()
                if pendingSessionID == sessionID {
                    startFallback(for: sessionID)
                }
            } catch {
                logger.error(
                    "Failed to end timer: \(error.localizedDescription, privacy: .private)")
                guard pendingSessionID == sessionID else { return }
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadAdhocAttribution() async {
        guard let sessionID = pendingSessionID, !adhocAttribution.isLoading else { return }
        let loadID = UUID()
        adhocAttribution.loadID = loadID
        adhocAttribution.isLoading = true
        adhocAttribution.loadError = nil
        do {
            let issues = try await daemonConnection.withClient { try await $0.listAllIssues() }
            await issueCreationService.loadDestinations()
            guard pendingSessionID == sessionID, adhocAttribution.loadID == loadID else { return }
            adhocAttribution.issues = issues
            if adhocAttribution.filter == .today, adhocAttribution.filteredIssues(today: daemonConnection.currentDate).isEmpty {
                adhocAttribution.filter = .all
            }
            adhocAttribution.loadError = issueCreationService.lastErrorMessage
        } catch {
            guard pendingSessionID == sessionID, adhocAttribution.loadID == loadID else { return }
            adhocAttribution.loadError = error.localizedDescription
        }
        if pendingSessionID == sessionID, adhocAttribution.loadID == loadID { adhocAttribution.isLoading = false }
    }

    /// Returns true when `sessionID` was the pending end and the end-session UI was finalized.
    func finalizeIfPending(sessionID: String) -> Bool {
        guard let pendingSessionID, pendingSessionID == sessionID else { return false }
        finalize()
        return true
    }

    func reconcile() {
        guard isSheetPresented else { return }

        if let pendingSessionID, timerService.snapshot.sessionID != pendingSessionID {
            finalize()
        }
    }

    func clear(preserveDraft: Bool = false) {
        if !preserveDraft {
            adhocAttribution = AdhocAttributionState()
            draftSessionID = nil
            commitMessage = ""
        }
        adhocAttribution.loadID = nil
        adhocAttribution.isLoading = false
        pendingSessionID = nil
        presentationSource = nil
        errorMessage = nil
        isSubmitting = false
    }

    func requestFocus() {
        focusRequest &+= 1
    }

    /// Developer previews show the end-session form without a real session.
    func setPreviewPending(source: EndSessionPresentationSource) {
        presentationSource = source
        pendingSessionID = "developer-preview"
        commitMessage = ""
        requestFocus()
    }

    private func startFallback(for sessionID: String) {
        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            guard self.isSubmitting, self.pendingSessionID == sessionID else { return }

            await self.timerService.refresh()
            await self.contextService.refresh()
            await self.dailyFocusService.refresh()
            await self.habitsService.refresh()
            await self.popoverStatsService.refresh()

            if self.timerService.snapshot.sessionID != sessionID {
                self.finalize()
            } else {
                self.isSubmitting = false
                self.errorMessage =
                    "The session end was sent, but confirmation did not arrive. Refresh and try again."
            }
        }
    }

    private func finalize() {
        fallbackTask?.cancel()
        fallbackTask = nil
        isSubmitting = false
        isSheetPresented = false
        let wasPresentedInHUD = presentationSource == .timerHUD
        clear()
        if wasPresentedInHUD {
            windowService.setTimerHUDCommitPresented(false)
        }
        onFinalized()
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
