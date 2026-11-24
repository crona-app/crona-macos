import XCTest

@testable import crona

@MainActor
final class AwaySettingsTests: XCTestCase {
    func testScheduledAwayDatesIncludeTodayAndFutureDatesOnly() {
        let settings = CronaCoreSettings(
            awayDates: ["2026-11-24"],
            restSpecificDates: ["2026-12-03", "2026-11-22", "2026-11-23", "2026-12-03"]
        )

        XCTAssertEqual(
            settings.scheduledAwayDates(from: "2026-11-23"),
            ["2026-11-23", "2026-12-03"]
        )
        XCTAssertTrue(settings.isConfiguredRestDate("2026-11-22"))
    }

    func testCalendarAlignsDatesToConfiguredWeekStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let november = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 24)))

        let cells = AwayCalendarMonth(containing: november, calendar: calendar).cells

        XCTAssertEqual(cells.count, 42)
        XCTAssertNil(cells[5])
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(cells[6])), 1)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(cells[35])), 30)
        XCTAssertNil(cells[36])
    }

    func testCalendarMovesAcrossYearBoundaryAndIncludesLeapDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let december = try XCTUnwrap(calendar.date(from: DateComponents(year: 2023, month: 12, day: 31)))
        let month = AwayCalendarMonth(containing: december, calendar: calendar)
        let february = AwayCalendarMonth(containing: month.shifted(by: 2), calendar: calendar)
        let days = february.cells.compactMap { $0 }

        XCTAssertEqual(calendar.component(.year, from: february.start), 2024)
        XCTAssertEqual(calendar.component(.month, from: february.start), 2)
        XCTAssertEqual(days.count, 29)
    }
}
