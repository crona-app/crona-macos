import Combine
import Foundation
import SwiftUI

@MainActor
final class IssueCreatorModel: ObservableObject {
    @Published var title = ""
    @Published var description = ""
    @Published var estimate = ""
    @Published var tags: [String] = []
    @Published var tagDraft = ""
    @Published var dueDate: Date?
    @Published var destinationID: Int64?
    @Published private(set) var isPresented = false
    @Published private(set) var isContentVisible = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var issueBeingEdited: DailyFocusIssue?
    @Published var success: IssueCreationSuccess?

    private let daemonConnection: DaemonConnectionService
    private let issueCreationService: IssueCreationService
    private let issueActionsService: IssueActionsService
    private let dailyFocusService: DailyFocusService
    private let contextService: ContextService
    private let canPresent: () -> Bool
    private let hasActiveFocusSession: () -> Bool
    private let focusIssue: (DailyFocusIssue) -> Void
    private var presentationGeneration: UInt = 0
    private var successDismissTask: Task<Void, Never>?

    init(
        daemonConnection: DaemonConnectionService,
        issueCreationService: IssueCreationService,
        issueActionsService: IssueActionsService,
        dailyFocusService: DailyFocusService,
        contextService: ContextService,
        canPresent: @escaping () -> Bool,
        hasActiveFocusSession: @escaping () -> Bool,
        focusIssue: @escaping (DailyFocusIssue) -> Void
    ) {
        self.daemonConnection = daemonConnection
        self.issueCreationService = issueCreationService
        self.issueActionsService = issueActionsService
        self.dailyFocusService = dailyFocusService
        self.contextService = contextService
        self.canPresent = canPresent
        self.hasActiveFocusSession = hasActiveFocusSession
        self.focusIssue = focusIssue
    }

    isolated deinit {
        successDismissTask?.cancel()
    }

    var defaultDueDate: Date {
        CronaCalendarDate.date(from: logicalDate) ?? Date()
    }

    private var logicalDate: String {
        guard let date = CronaCalendarDate.date(from: daemonConnection.currentDate),
            CronaCalendarDate.string(from: date) == daemonConnection.currentDate
        else { return DailyFocusService.todayString() }
        return daemonConnection.currentDate
    }

    func presentCreator() {
        guard daemonConnection.connectionState == .connected,
            !isSubmitting,
            !isPresented,
            canPresent()
        else { return }
        issueCreationService.clearError()
        issueBeingEdited = nil
        title = ""
        description = ""
        estimate = ""
        tags = []
        tagDraft = ""
        dueDate = defaultDueDate
        destinationID = contextService.snapshot.streamID
        isContentVisible = false
        isPresented = true
        presentationGeneration &+= 1
        let generation = presentationGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                self.isPresented,
                generation == self.presentationGeneration
            else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.isContentVisible = true
            }
        }
        Task {
            await issueCreationService.loadDestinations()
            if !issueCreationService.destinations.contains(where: {
                $0.streamID == destinationID
            }) {
                destinationID = nil
            }
        }
    }

    func presentEditor(for issue: DailyFocusIssue) {
        guard daemonConnection.connectionState == .connected,
            !isSubmitting,
            canPresent(),
            !isPresented
        else { return }
        issueCreationService.clearError()
        issueBeingEdited = issue
        title = issue.title
        description = issue.description ?? ""
        estimate = issue.estimateMinutes.map(String.init) ?? ""
        dueDate = issue.todoForDate.flatMap(CronaCalendarDate.date(from:))
        destinationID = issue.streamID
        isContentVisible = false
        isPresented = true
        presentationGeneration &+= 1
        let generation = presentationGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.isPresented,
                generation == self.presentationGeneration
            else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.isContentVisible = true
            }
        }
    }

    func cancel() {
        guard !isSubmitting else { return }
        issueCreationService.clearError()
        issueBeingEdited = nil
        dismissPresentation()
    }

    func submit(followUp: IssueCreationFollowUp = .close) {
        guard !isSubmitting,
            !issueCreationService.isCreating,
            issueActionsService.actionInFlightIssueID == nil,
            followUp != .focus || !hasActiveFocusSession()
        else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimateText = estimate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120,
            description.count <= 2_000,
            let streamID = destinationID
        else { return }
        guard case .success(let estimate) = FlexibleDurationParser.optionalMinutes(estimateText)
        else { return }
        let logicalDate = dueDate.map(CronaCalendarDate.string(from:))
        isSubmitting = true
        if let issueBeingEdited {
            let issue = issueBeingEdited
            Task {
                defer { isSubmitting = false }
                let succeeded = await issueActionsService.updateIssue(
                    issue: issue,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    estimateMinutes: estimate,
                    todoForDate: logicalDate
                )
                if succeeded {
                    self.issueBeingEdited = nil
                    await dismissPresentationAndWait()
                }
            }
            return
        }

        tags = TagInput.committing(tagDraft, into: tags)
        tagDraft = ""
        let request = CronaCreateIssueRequest(
            streamID: streamID,
            title: title,
            description: description.isEmpty ? nil : description,
            estimateMinutes: estimate,
            todoForDate: logicalDate,
            tags: tags.isEmpty ? nil : tags
        )
        Task {
            defer { isSubmitting = false }
            guard let created = await issueCreationService.create(request) else { return }
            let issue = DailyFocusIssue(
                id: created.id,
                streamID: created.streamID,
                title: created.title,
                status: created.status,
                estimateMinutes: created.estimateMinutes,
                workedSeconds: created.workedSeconds,
                todoForDate: created.todoForDate,
                repoName: created.repoName,
                streamName: created.streamName,
                description: created.description,
                notes: created.notes,
                pinnedDaily: created.pinnedDaily,
                tags: created.tags ?? []
            )
            await dailyFocusService.refresh()

            switch followUp {
            case .more:
                success = nil
                issueBeingEdited = nil
                self.title = ""
                self.description = ""
                self.estimate = ""
                self.tags = []
                self.tagDraft = ""
                destinationID = created.streamID
            case .focus:
                successDismissTask?.cancel()
                success = nil
                await dismissPresentationAndWait()
                if hasActiveFocusSession() {
                    success = IssueCreationSuccess(
                        issue: issue, plannedForToday: created.todoForDate == self.logicalDate)
                    scheduleSuccessDismissal()
                } else {
                    focusIssue(issue)
                }
            case .close:
                success = IssueCreationSuccess(
                    issue: issue, plannedForToday: created.todoForDate == self.logicalDate)
                await dismissPresentationAndWait()
                scheduleSuccessDismissal()
            }
        }
    }

    func startFocusFromCreatedIssue() {
        guard let success,
            success.plannedForToday,
            !hasActiveFocusSession()
        else { return }
        successDismissTask?.cancel()
        self.success = nil
        focusIssue(success.issue)
    }

    func dismissSuccess() {
        successDismissTask?.cancel()
        success = nil
    }

    private func scheduleSuccessDismissal() {
        successDismissTask?.cancel()
        successDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.success = nil
        }
    }

    private func dismissPresentation() {
        guard isPresented else { return }
        presentationGeneration &+= 1
        let generation = presentationGeneration
        withAnimation(.easeInOut(duration: 0.18)) {
            isContentVisible = false
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self,
                !self.isContentVisible,
                generation == self.presentationGeneration
            else { return }
            self.isPresented = false
            await Task.yield()
        }
    }

    private func dismissPresentationAndWait() async {
        presentationGeneration &+= 1
        let generation = presentationGeneration
        withAnimation(.easeInOut(duration: 0.18)) {
            isContentVisible = false
        }
        try? await Task.sleep(for: .milliseconds(180))
        guard !isContentVisible,
            generation == presentationGeneration
        else { return }
        isPresented = false
        await Task.yield()
    }
}
