import Foundation

enum CronaAdhocResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case attach, create, keep
    var id: String { rawValue }
    var title: String {
        switch self {
        case .attach: "Attach to Issue"
        case .create: "Create Issue"
        case .keep: "Keep Ad Hoc"
        }
    }
}

enum AdhocIssueFilter: String, CaseIterable, Identifiable {
    case today = "Due Today", overdue = "Overdue", pinned = "Pinned", all = "All"
    var id: String { rawValue }
}

struct AdhocAttributionState {
    var resolution: CronaAdhocResolution?
    var issues: [CronaIssue] = []
    var filter: AdhocIssueFilter = .today
    var selectedIssueID: Int64?
    var destinationID: Int64?
    var repoID: Int64?
    var title = ""
    var description = ""
    var estimateInput: String?
    var estimateMinutes = 0
    var date = ""
    var createdIssue: CronaIssue?
    var loadID: UUID?
    var isLoading = false
    var loadError: String?

    static func initial(elapsedSeconds: Int, date: String, streamID: Int64?) -> Self {
        Self(destinationID: streamID, estimateMinutes: max(0, (elapsedSeconds + 899) / 900 * 15), date: date)
    }

    func filteredIssues(today: String) -> [CronaIssue] {
        issues.filter { issue in
            guard ["planned", "ready", "in_progress"].contains(issue.status) else { return false }
            switch filter {
            case .today: return issue.todoForDate == today
            case .overdue: return issue.todoForDate.map { !$0.isEmpty && $0 < today } ?? false
            case .pinned: return issue.pinnedDaily
            case .all: return true
            }
        }
    }
}

enum AdhocCompletionLayout {
    static func height(for resolution: CronaAdhocResolution?) -> CGFloat {
        switch resolution {
        case .attach: 580
        case .create: 560
        case .keep: 390
        case nil: 390
        }
    }
}

extension CompanionAppState {
    var activeFocusTitle: String? {
        timerService.snapshot.adhoc ? "Ad Hoc Focus" : contextService.snapshot.issueTitle
    }
}
