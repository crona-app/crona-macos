import Foundation

enum DailySection: String, CaseIterable, Identifiable {
    case planned, overdue, upcoming, inbox

    var id: String { rawValue }
}

/// The Issues tab's sections for one day, matching the TUI's Daily view
/// (`buildDailyScopedIssues` in crona/tui/internal/tui/selection/snapshot_scoped.go).
struct DailyIssueSections: Equatable {
    static let upcomingDays = 7

    var planned: [DailyFocusIssue] = []
    var overdue: [DailyFocusIssue] = []
    var upcoming: [DailyFocusIssue] = []
    /// Open issues waiting in Crona's system Inbox stream to be sorted into a real stream.
    var inbox: [DailyFocusIssue] = []

    func issues(in section: DailySection) -> [DailyFocusIssue] {
        switch section {
        case .planned: return planned
        case .overdue: return overdue
        case .upcoming: return upcoming
        case .inbox: return inbox
        }
    }

    /// The Inbox segment only appears while it has something to sort.
    var visibleSections: [DailySection] {
        inbox.isEmpty ? [.planned, .overdue, .upcoming] : DailySection.allCases
    }

    static func build(
        issues: [CronaIssue], plan: CronaDailyPlan?, date: String, systemStreamIDs: Set<Int64> = []
    ) -> DailyIssueSections {
        let listed = issues.filter { $0.adhoc != true }
        let open = listed.filter { !isClosed($0) }
        var plannedEntries: [Int64: CronaDailyPlanEntry] = [:]
        var carriedAwayEntries: [Int64: CronaDailyPlanEntry] = [:]
        if let plan, plan.date == date {
            for entry in plan.entries {
                switch entry.status {
                case "planned": plannedEntries[entry.issueID] = entry
                case "carried": carriedAwayEntries[entry.issueID] = entry
                default: break
                }
            }
        }
        func project(_ issue: CronaIssue) -> DailyFocusIssue {
            let entry = plannedEntries[issue.id]
            return DailyFocusIssue(
                issue: issue,
                penalty: entry.flatMap(DailyFocusPenalty.from),
                carry: entry.flatMap(DailyFocusCarry.from),
                carriedAway: carriedAwayEntries[issue.id] != nil,
                carriedToDate: carriedAwayEntries[issue.id]?.carriedToDate
            )
        }

        var sections = DailyIssueSections()
        // Open pinned issues lead whatever their date, then everything else due that day,
        // closed or not, so a day keeps the work finished on it.
        let leadsPlanned: (CronaIssue) -> Bool = { $0.pinnedDaily && !isClosed($0) }
        sections.planned =
            open.filter(leadsPlanned).map(project)
            + listed.filter { !leadsPlanned($0) && due($0) == date }.map(project)
            // The day keeps the worked copy of issues it carried to a later day.
            + listed.filter {
                carriedAwayEntries[$0.id] != nil && !leadsPlanned($0) && due($0) != date
            }.map(project)
        sections.overdue = open.filter { issue in
            guard let due = due(issue) else { return false }
            return due < date
        }.map(project)
        let horizon = CronaCalendarDate.adding(days: upcomingDays, to: date) ?? date
        // Stable by due date, like the TUI's sort.SliceStable.
        sections.upcoming = open.enumerated().compactMap { offset, issue -> (String, Int, CronaIssue)? in
            guard let due = due(issue), due > date, due <= horizon else { return nil }
            return (due, offset, issue)
        }
        .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        .map { project($0.2) }
        sections.inbox = open.filter { systemStreamIDs.contains($0.streamID) }.map(project)
        return sections
    }

    private static func isClosed(_ issue: CronaIssue) -> Bool {
        issue.status == "done" || issue.status == "abandoned"
    }

    private static func due(_ issue: CronaIssue) -> String? {
        guard let value = issue.todoForDate?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        return value
    }
}
