import SwiftUI

/// Planned / Overdue / Upcoming switch for the Issues tab, mirroring the TUI's Daily sections.
struct DailySectionPicker: View {
    @ObservedObject private var dailyIssues: DailyIssuesModel

    init(dailyIssues: DailyIssuesModel) {
        self._dailyIssues = ObservedObject(wrappedValue: dailyIssues)
    }

    var body: some View {
        Picker("Section", selection: $dailyIssues.section) {
            ForEach(DailySection.allCases) { section in
                Text(Self.title(for: section, overdueCount: dailyIssues.sections.overdue.count))
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    static func title(for section: DailySection, overdueCount: Int) -> String {
        switch section {
        case .planned: return "Planned"
        case .overdue: return overdueCount > 0 ? "Overdue (\(overdueCount))" : "Overdue"
        case .upcoming: return "Upcoming"
        }
    }

    static func emptyText(for section: DailySection) -> String {
        switch section {
        case .planned: return "Nothing planned"
        case .overdue: return "Nothing overdue"
        case .upcoming: return "Nothing in the next \(DailyIssueSections.upcomingDays) days"
        }
    }
}
