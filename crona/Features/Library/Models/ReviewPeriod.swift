import Foundation

enum ReviewPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    var id: Self { self }

    func range(anchor: String, today: String, weekStart: String) -> ReviewRange {
        var calendar = LibraryDates.calendar
        calendar.firstWeekday = weekStart == "sunday" ? 1 : (weekStart == "saturday" ? 7 : 2)
        let component: Calendar.Component = self == .week ? .weekOfYear : .month
        let interval = calendar.dateInterval(of: component, for: LibraryDates.date(anchor))!
        let start = LibraryDates.string(interval.start)
        let fullEnd = LibraryDates.string(calendar.date(byAdding: .day, value: -1, to: interval.end)!)
        let end = min(fullEnd, today)
        let previousStartDate = calendar.date(byAdding: component, value: -1, to: interval.start)!
        let previousStart = LibraryDates.string(previousStartDate)
        let previousFullEnd = LibraryDates.adding(-1, to: start)
        let elapsed = calendar.dateComponents([.day], from: interval.start, to: LibraryDates.date(end)).day ?? 0
        let previousEnd =
            end < fullEnd ? min(LibraryDates.adding(elapsed, to: previousStart), previousFullEnd) : previousFullEnd
        return ReviewRange(start: start, end: end, previousStart: previousStart, previousEnd: previousEnd)
    }

    func shifted(_ anchor: String, by amount: Int) -> String {
        let component: Calendar.Component = self == .week ? .weekOfYear : .month
        return LibraryDates.string(
            LibraryDates.calendar.date(byAdding: component, value: amount, to: LibraryDates.date(anchor))!)
    }
}

struct ReviewRange: Hashable {
    let start: String
    let end: String
    let previousStart: String
    let previousEnd: String

    var dates: [String] {
        var dates: [String] = []
        var date = start
        while date <= end {
            dates.append(date)
            date = LibraryDates.adding(1, to: date)
        }
        return dates
    }
}
