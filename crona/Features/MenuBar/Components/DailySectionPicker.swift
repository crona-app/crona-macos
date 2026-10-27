import SwiftUI

/// Planned / Overdue / Upcoming switch for the Issues tab, mirroring the TUI's Daily sections.
/// Uses the popover's own capsule control so it matches the tab bar.
struct DailySectionPicker: View {
    @ObservedObject private var dailyIssues: DailyIssuesModel

    init(dailyIssues: DailyIssuesModel) {
        self._dailyIssues = ObservedObject(wrappedValue: dailyIssues)
    }

    var body: some View {
        let sections = dailyIssues.sections
        SegmentedControl(
            selection: Binding(
                get: { dailyIssues.section },
                set: { dailyIssues.section = $0 }
            ),
            title: { Self.title(for: $0, sections: sections) },
            items: sections.visibleSections
        )
    }

    static func title(for section: DailySection, sections: DailyIssueSections) -> String {
        switch section {
        case .inbox: return "Inbox (\(sections.inbox.count))"
        default: return title(for: section, overdueCount: sections.overdue.count)
        }
    }

    static func title(for section: DailySection, overdueCount: Int) -> String {
        switch section {
        case .planned: return "Planned"
        case .overdue: return overdueCount > 0 ? "Overdue (\(overdueCount))" : "Overdue"
        case .upcoming: return "Upcoming"
        case .inbox: return "Inbox"
        }
    }

    static func emptyText(for section: DailySection) -> String {
        switch section {
        case .planned: return "Nothing planned"
        case .overdue: return "Nothing overdue"
        case .upcoming: return "Nothing in the next \(DailyIssueSections.upcomingDays) days"
        case .inbox: return "Inbox is empty"
        }
    }

    static func emptyHint(for section: DailySection) -> String {
        switch section {
        case .planned: return "Pin an issue or give it this day's due date to plan it."
        case .overdue: return "Every issue due before this day is closed."
        case .upcoming: return "Issues due in the coming week show up here."
        case .inbox: return "Captured issues without a stream land here."
        }
    }
}
