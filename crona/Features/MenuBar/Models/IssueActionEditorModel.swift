import Combine
import Foundation

struct ManualSessionDraft: Equatable {
    var summary = ""
    var date = ""
    var notes = ""
    var workHours = 1
    var workMinutes = 0
    var breakHours = 0
    var breakMinutes = 0
    var timesEnabled = false
    var startHour = 9
    var startMinute = 0
    var startPeriod = "AM"
    var endHour = 10
    var endMinute = 45
    var endPeriod = "AM"
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
            let workMinutes = draft.workHours * 60 + draft.workMinutes
            let breakMinutes = draft.breakHours * 60 + draft.breakMinutes
            guard workMinutes > 0 else {
                manualSessionError = "Work duration must be a positive duration."
                return
            }
            guard isValidManualDate(draft.date) else {
                manualSessionError = "Choose a valid session date."
                return
            }
            let startTime =
                draft.timesEnabled
                ? formattedManualClock(
                    hour: draft.startHour, minute: draft.startMinute,
                    period: draft.startPeriod)
                : nil
            let endTime =
                draft.timesEnabled
                ? formattedManualClock(
                    hour: draft.endHour, minute: draft.endMinute,
                    period: draft.endPeriod)
                : nil
            Task {
                let request = CronaManualSessionLogRequest(
                    issueID: issue.id,
                    date: manualSession.date.trimmingCharacters(in: .whitespacesAndNewlines),
                    workDurationSeconds: workMinutes * 60,
                    breakDurationSeconds: breakMinutes * 60,
                    startTime: startTime,
                    endTime: endTime,
                    commitMessage: optionalTrimmed(manualSession.summary),
                    notes: optionalTrimmed(manualSession.notes)
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

    private func formattedManualClock(hour: Int, minute: Int, period: String) -> String {
        var hour24 = hour % 12
        if period == "PM" { hour24 += 12 }
        return String(format: "%02d:%02d", hour24, minute)
    }

    private func isValidManualDate(_ value: String) -> Bool {
        CronaCalendarDate.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
