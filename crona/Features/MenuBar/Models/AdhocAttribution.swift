import Foundation

enum CronaAdhocResolution: String, Codable, CaseIterable, Identifiable {
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
    var adhocCompletionHeight: CGFloat {
        (adhocAttribution.resolution == .create && adhocAttribution.createdIssue != nil
            ? AdhocCompletionLayout.height(for: .keep)
            : AdhocCompletionLayout.height(for: adhocAttribution.resolution))
            + (adhocAttribution.loadError != nil || endSessionErrorMessage != nil ? 48 : 0)
    }

    var endSessionActionTitle: String {
        guard timerService.snapshot.adhoc else { return "End Session" }
        switch adhocAttribution.resolution {
        case .attach: return "Attach & Finish"
        case .create: return adhocAttribution.createdIssue == nil ? "Create & Finish" : "Retry & Finish"
        case .keep: return "Keep Ad Hoc & Finish"
        case nil: return "End Session"
        }
    }

    var canSubmitEndSession: Bool {
        guard !isSubmittingEndSession else { return false }
        guard timerService.snapshot.adhoc else { return true }
        guard let resolution = adhocAttribution.resolution else { return false }
        return resolution != .create || adhocAttribution.createdIssue != nil || adhocAttribution.estimateMinutes >= 0
    }

    var adhocElapsedSeconds: Int {
        guard let start = timerService.snapshot.sessionStartTime else { return max(0, timerService.snapshot.elapsedSeconds) }
        return max(0, Int(Date().timeIntervalSince(start)))
    }

    var activeFocusTitle: String? {
        timerService.snapshot.adhoc ? "Ad Hoc Focus" : contextService.snapshot.issueTitle
    }

    func loadAdhocAttribution() async {
        guard let sessionID = pendingEndSessionID, !adhocAttribution.isLoading else { return }
        let loadID = UUID()
        adhocAttribution.loadID = loadID
        adhocAttribution.isLoading = true
        adhocAttribution.loadError = nil
        do {
            let issues = try await daemonConnection.withClient { try await $0.listAllIssues() }
            await issueCreationService.loadDestinations()
            guard pendingEndSessionID == sessionID, adhocAttribution.loadID == loadID else { return }
            adhocAttribution.issues = issues
            if adhocAttribution.filter == .today, adhocAttribution.filteredIssues(today: daemonConnection.currentDate).isEmpty {
                adhocAttribution.filter = .all
            }
            adhocAttribution.loadError = issueCreationService.lastErrorMessage
        } catch {
            guard pendingEndSessionID == sessionID, adhocAttribution.loadID == loadID else { return }
            adhocAttribution.loadError = error.localizedDescription
        }
        if pendingEndSessionID == sessionID, adhocAttribution.loadID == loadID { adhocAttribution.isLoading = false }
    }
}
