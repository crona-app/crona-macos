import XCTest

@testable import crona

@MainActor
final class ReviewPeriodTests: XCTestCase {
    func testWeekRespectsDaemonWeekStartAndMatchesElapsedComparison() {
        let monday = ReviewPeriod.week.range(anchor: "2026-11-11", today: "2026-11-11", weekStart: "monday")
        XCTAssertEqual(
            monday,
            ReviewRange(start: "2026-11-09", end: "2026-11-11", previousStart: "2026-11-02", previousEnd: "2026-11-04"))
        let sunday = ReviewPeriod.week.range(anchor: "2026-11-11", today: "2026-11-11", weekStart: "sunday")
        XCTAssertEqual(sunday.start, "2026-11-08")
        XCTAssertEqual(sunday.previousEnd, "2026-11-04")
    }

    func testMonthComparisonCapsAtPreviousMonthEndAndSupportsLeapYears() {
        let march = ReviewPeriod.month.range(anchor: "2024-03-30", today: "2024-03-30", weekStart: "monday")
        XCTAssertEqual(march.previousStart, "2024-02-01")
        XCTAssertEqual(march.previousEnd, "2024-02-29")
        let january = ReviewPeriod.month.range(anchor: "2026-01-03", today: "2026-01-03", weekStart: "monday")
        XCTAssertEqual(january.previousStart, "2025-12-01")
        XCTAssertEqual(january.previousEnd, "2025-12-03")
    }

    func testTimestampFormattingUsesDaemonTimezoneAndPreferredDate() throws {
        let settings = CronaCoreSettings(dateDisplayPreset: "iso")
        let shown = try XCTUnwrap(
            LibraryDates.clock("2026-11-14T23:30:00Z", timezone: "Asia/Kolkata", includeDate: true, settings: settings))
        XCTAssertTrue(shown.hasPrefix("2026-11-15 at "))
        XCTAssertNil(LibraryDates.clock("invalid", timezone: "Asia/Kolkata"))
    }

    func testCompletedPeriodsCompareWithFullPreviousPeriod() {
        let range = ReviewPeriod.month.range(anchor: "2026-02-15", today: "2026-11-15", weekStart: "monday")
        XCTAssertEqual(range.end, "2026-02-28")
        XCTAssertEqual(range.previousEnd, "2026-01-31")
        XCTAssertEqual(range.dates.count, 28)
    }
}
