import Combine
import Foundation

struct ManualSessionDraft: Equatable {
    var summary = ""
    var date = ""
    var notes = ""
    var workDuration = "1h0m"
    var breakDuration = "0m"
    var timesEnabled = false
    var startTime = "09:00"
    var endTime = ""
}

@MainActor
final class IssueActionEditorModel: ObservableObject {
    @Published var editor: IssueActionEditor?
    @Published var note = ""
    @Published var date = Date()
    @Published var manualSession = ManualSessionDraft()
    @Published var manualSessionError: String?

    private let daemonConnection: DaemonConnectionService
    private let issueActionsService: IssueActionsService
    private let dailyFocusService: DailyFocusService
    private let onIssueDeleted: (Int64) -> Void

    init(
        daemonConnection: DaemonConnectionService,
        issueActionsService: IssueActionsService,
        dailyFocusService: DailyFocusService,
        onIssueDeleted: @escaping (Int64) -> Void
    ) {
        self.daemonConnection = daemonConnection
        self.issueActionsService = issueActionsService
        self.dailyFocusService = dailyFocusService
        self.onIssueDeleted = onIssueDeleted
    }

    func requestStatusChange(issue: DailyFocusIssue, status: CronaIssueStatus) {
        issueActionsService.clearError()
        guard status.notePrompt != nil else {
            Task {
                _ = await issueActionsService.changeStatus(
                    issue: issue,
                    status: status,
                    note: nil
                )
            }
            return
        }
        note = ""
        editor = .status(issue: issue, status: status)
    }

    func setDueDate(_ issue: DailyFocusIssue, date: String) {
        issueActionsService.clearError()
        Task {
            _ = await issueActionsService.setDueDate(issue: issue, date: date)
        }
    }

    func clearDueDate(_ issue: DailyFocusIssue) {
        issueActionsService.clearError()
        Task {
            _ = await issueActionsService.clearDueDate(issue: issue)
        }
    }

    func presentCustomDueDate(for issue: DailyFocusIssue) {
        issueActionsService.clearError()
        let initialValue = issue.todoForDate ?? dailyFocusService.snapshot.date
        date = CronaCalendarDate.date(from: initialValue) ?? Date()
        editor = .dueDate(issue: issue)
    }

    func presentManualSession(for issue: DailyFocusIssue) {
        issueActionsService.clearError()
        manualSession = ManualSessionDraft(
            date: dailyFocusService.snapshot.date.isEmpty
                ? (daemonConnection.currentDate.isEmpty
                    ? DailyFocusService.todayString() : daemonConnection.currentDate)
                : dailyFocusService.snapshot.date
        )
        manualSessionError = nil
        editor = .manualSession(issue: issue)
    }

    func cancel() {
        guard issueActionsService.actionInFlightIssueID == nil else { return }
        editor = nil
        note = ""
        manualSessionError = nil
    }

    func presentDelete(for issue: DailyFocusIssue) {
        issueActionsService.clearError()
        editor = .delete(issue: issue)
    }

    func submit() {
        guard let editor else { return }
        switch editor {
        case .status(let issue, let status):
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !status.requiresNote || !trimmedNote.isEmpty else {
                return
            }
            Task {
                let succeeded = await issueActionsService.changeStatus(
                    issue: issue,
                    status: status,
                    note: trimmedNote.isEmpty ? nil : trimmedNote
                )
                if succeeded {
                    self.editor = nil
                    note = ""
                }
            }
        case .dueDate(let issue):
            let date = CronaCalendarDate.string(from: date)
            Task {
                let succeeded = await issueActionsService.setDueDate(issue: issue, date: date)
                if succeeded {
                    self.editor = nil
                }
            }
        case .manualSession(let issue):
            manualSessionError = nil
            let draft = manualSession
            guard let workMinutes = DurationInput.minutes(draft.workDuration), workMinutes > 0 else {
                manualSessionError = "Work duration must be a positive duration."
                return
            }
            guard let breakMinutes = DurationInput.minutes(draft.breakDuration) else {
                manualSessionError = "Enter a valid break duration, such as 13m or 1h07m."
                return
            }
            guard isValidManualDate(draft.date) else {
                manualSessionError = "Choose a valid session date."
                return
            }
            let startTime = draft.timesEnabled ? optionalTrimmed(draft.startTime) : nil
            let endTime = draft.timesEnabled ? optionalTrimmed(draft.endTime) : nil
            guard [startTime, endTime].compactMap({ $0 }).allSatisfy(Self.isValidClock) else {
                manualSessionError = "Enter times as HH:mm, such as 09:07 or 17:43."
                return
            }
            Task {
                let request = CronaManualSessionLogRequest(
                    issueID: issue.id,
                    date: draft.date.trimmingCharacters(in: .whitespacesAndNewlines),
                    workDurationSeconds: workMinutes * 60,
                    breakDurationSeconds: breakMinutes * 60,
                    startTime: startTime,
                    endTime: endTime,
                    commitMessage: optionalTrimmed(draft.summary),
                    notes: optionalTrimmed(draft.notes)
                )
                let succeeded = await issueActionsService.logManualSession(request)
                if succeeded {
                    self.editor = nil
                    manualSessionError = nil
                }
            }
        case .delete(let issue):
            Task {
                let succeeded = await issueActionsService.deleteIssue(issue)
                if succeeded {
                    onIssueDeleted(issue.id)
                    self.editor = nil
                }
            }
        }
    }

    private static func isValidClock(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    private func isValidManualDate(_ value: String) -> Bool {
        CronaCalendarDate.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
