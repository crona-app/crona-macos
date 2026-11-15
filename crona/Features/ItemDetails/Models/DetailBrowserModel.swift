import Combine
import Foundation

@MainActor
final class DetailBrowserModel: ObservableObject {
    enum Source: Equatable {
        case issues(DailySection)
        case habits, activity
    }
    @Published private(set) var source: Source = .activity
    @Published private(set) var activityIssue: DailyFocusIssue?
    @Published private(set) var issueID: Int64?
    @Published private(set) var habitID: Int64?

    func open(issue: DailyFocusIssue, section: DailySection?) {
        source = section.map(Source.issues) ?? .activity
        activityIssue = section == nil ? issue : nil
        issueID = issue.id
        habitID = nil
    }
    func open(habit: HabitRowModel) {
        source = .habits
        habitID = habit.id
        issueID = nil
        activityIssue = nil
    }
    func ids(issues: DailyIssueSections, habits: [HabitRowModel]) -> [Int64] {
        switch source {
        case .issues(let section): return issues.issues(in: section).map(\.id)
        case .habits: return habits.map(\.id)
        case .activity: return []
        }
    }
    func neighbor(_ offset: Int, ids: [Int64]) -> Int64? {
        guard let id = issueID ?? habitID, let index = ids.firstIndex(of: id), ids.indices.contains(index + offset)
        else { return nil }
        return ids[index + offset]
    }
    func select(_ id: Int64) {
        if source == .habits { habitID = id } else { issueID = id }
    }
}
