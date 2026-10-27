import Foundation

extension DailyIssueSections {
    func filtered(_ keep: (DailyFocusIssue) -> Bool) -> DailyIssueSections {
        var result = self
        result.planned = planned.filter(keep)
        result.overdue = overdue.filter(keep)
        result.upcoming = upcoming.filter(keep)
        result.inbox = inbox.filter(keep)
        return result
    }
}

extension HabitsSnapshot {
    func filtered(by filter: CronaTagFilter, known: Set<String>) -> HabitsSnapshot {
        guard !filter.isEmpty else { return self }
        var result = self
        result.items = items.filter { filter.matches($0.tags, known: known) }
        return result
    }
}
