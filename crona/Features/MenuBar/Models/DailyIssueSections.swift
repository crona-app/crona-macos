import Foundation

enum DailySection: String, CaseIterable, Identifiable {
    case planned, overdue, upcoming

    var id: String { rawValue }
}

/// The Issues tab's sections for one day, matching the TUI's Daily view
/// (`buildDailyScopedIssues` in crona/tui/internal/tui/selection/snapshot_scoped.go).
struct DailyIssueSections: Equatable {
    static let upcomingDays = 7

    var planned: [DailyFocusIssue] = []
    var overdue: [DailyFocusIssue] = []
    var upcoming: [DailyFocusIssue] = []

    func issues(in section: DailySection) -> [DailyFocusIssue] {
        switch section {
        case .planned: return planned
        case .overdue: return overdue
        case .upcoming: return upcoming
        }
    }

    static func build(issues: [CronaIssue], plan: CronaDailyPlan?, date: String) -> DailyIssueSections {
        let listed = issues.filter { $0.adhoc != true }
        let open = listed.filter { !isClosed($0) }
        var plannedEntries: [Int64: CronaDailyPlanEntry] = [:]
        var carriedAwayIDs = Set<Int64>()
        if let plan, plan.date == date {
            for entry in plan.entries {
                switch entry.status {
                case "planned": plannedEntries[entry.issueID] = entry
                case "carried": carriedAwayIDs.insert(entry.issueID)
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
                carriedAway: carriedAwayIDs.contains(issue.id)
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
                carriedAwayIDs.contains($0.id) && !leadsPlanned($0) && due($0) != date
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
