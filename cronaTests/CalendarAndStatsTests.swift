import XCTest
@testable import crona

@MainActor
final class CalendarAndStatsTests: DaemonTestCase {
    func testCoreSettingsDecodeAndClassifyAwayDates() throws {
        let settings = try JSONDecoder().decode(
            CronaCoreSettings.self,
            from: """
            {
              "awayModeEnabled":false,
              "awayDates":["2026-08-10"],
              "restWeekdays":[0],
              "restSpecificDates":["2026-08-12"]
            }
            """.data(using: .utf8)!
        )

        XCTAssertTrue(settings.isHistoricalAwayDate("2026-08-10"))
        XCTAssertTrue(settings.isConfiguredRestDate("2026-08-12"))
        XCTAssertTrue(settings.isConfiguredRestDate("2026-08-16"))
        XCTAssertFalse(settings.isConfiguredRestDate("2026-08-10"))
    }

    func testCoreSettingsDecodeDateDisplaySettingsAndFormatPresets() throws {
        let settings = try JSONDecoder().decode(
            CronaCoreSettings.self,
            from: """
            {
              "awayModeEnabled": false,
              "dateDisplayPreset": "us",
              "dateDisplayFormat": ""
            }
            """.data(using: .utf8)!
        )

        XCTAssertEqual(settings.dateDisplayPreset, "us")
        XCTAssertEqual(
            CronaDateDisplayFormatter.string(fromISODate: "2026-08-16", settings: settings),
            "08/16/2026"
        )
    }

    func testCronaDateDisplayFormatterSupportsCustomMomentPatternsAndLiterals() {
        let settings = CronaCoreSettings(
            dateDisplayPreset: "custom",
            dateDisplayFormat: "Do MMM YYYY [focus]"
        )

        XCTAssertEqual(
            CronaDateDisplayFormatter.string(fromISODate: "2026-08-01", settings: settings),
            "1st Aug 2026 focus"
        )
    }

    func testCalendarPrefetchMergesScoreWithoutDiscardingMetrics() {
        let metrics = CronaDailyMetricsDay(
            date: "2026-08-09", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, totalIssues: 5, completedIssues: 2, abandonedIssues: 0,
            totalEstimatedMinutes: 120, habitDueCount: 1, habitCompletedCount: 1,
            habitFailedCount: 0
        )
        let score = CronaFocusScoreSummary(
            startDate: "2026-08-09", endDate: "2026-08-09", score: 87,
            level: "strong", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, focusDays: 1, days: 1, targetWorkedSeconds: 7_200
        )
        let existing = PopoverStatsSnapshot(date: "2026-08-09", todayMetrics: metrics)

        let merged = PopoverStatsService.mergingCalendarScore(
            score,
            into: existing,
            date: "2026-08-09"
        )

        XCTAssertEqual(merged.todayMetrics, metrics)
        XCTAssertEqual(merged.focusScore, score)
        XCTAssertEqual(merged.scoreMessage, PopoverStatsService.message(for: "strong"))
    }

    func testTodayMetricsSuccessPreservesExistingFocusScore() {
        let metrics = CronaDailyMetricsDay(
            date: "2026-08-09", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, totalIssues: 5, completedIssues: 2, abandonedIssues: 0,
            totalEstimatedMinutes: 120, habitDueCount: 1, habitCompletedCount: 1,
            habitFailedCount: 0
        )
        let score = CronaFocusScoreSummary(
            startDate: "2026-08-09", endDate: "2026-08-09", score: 87,
            level: "strong", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, focusDays: 1, days: 1, targetWorkedSeconds: 7_200
        )
        let existing = PopoverStatsSnapshot(date: "2026-08-09", focusScore: score)

        let merged = PopoverStatsService.mergingTodayMetrics(metrics, into: existing)

        XCTAssertEqual(merged.todayMetrics, metrics)
        XCTAssertEqual(merged.focusScore, score)
    }

    func testTodayFocusScoreSuccessPreservesExistingMetrics() {
        let metrics = CronaDailyMetricsDay(
            date: "2026-08-09", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, totalIssues: 5, completedIssues: 2, abandonedIssues: 0,
            totalEstimatedMinutes: 120, habitDueCount: 1, habitCompletedCount: 1,
            habitFailedCount: 0
        )
        let score = CronaFocusScoreSummary(
            startDate: "2026-08-09", endDate: "2026-08-09", score: 87,
            level: "strong", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, focusDays: 1, days: 1, targetWorkedSeconds: 7_200
        )
        let existing = PopoverStatsSnapshot(date: "2026-08-09", todayMetrics: metrics)

        let merged = PopoverStatsService.mergingTodayFocusScore(score, into: existing)

        XCTAssertEqual(merged.todayMetrics, metrics)
        XCTAssertEqual(merged.focusScore, score)
    }

    func testCalendarDayAccessibilityDescribesStateWithoutColor() {
        let label = CalendarDayAccessibility.label(
            date: "2026-08-09",
            isAway: true,
            isToday: true,
            isSelected: true,
            score: 87,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertTrue(label.contains("Aug"))
        XCTAssertTrue(label.contains("away day"))
        XCTAssertTrue(label.contains("today"))
        XCTAssertTrue(label.contains("selected"))
        XCTAssertTrue(label.contains("focus score 87"))
    }

    func testCalendarMonthRangeIsBoundedByDisplayedMonthAndToday() {
        let pastMonth = PopoverStatsService.monthRange(
            for: "2026-07-15",
            through: "2026-08-18"
        )
        XCTAssertEqual(pastMonth.first, "2026-07-01")
        XCTAssertEqual(pastMonth.last, "2026-07-31")
        XCTAssertEqual(pastMonth.count, 31)

        let currentMonth = PopoverStatsService.monthRange(
            for: "2026-08-01",
            through: "2026-08-18"
        )
        XCTAssertEqual(currentMonth.first, "2026-08-01")
        XCTAssertEqual(currentMonth.last, "2026-08-18")
        XCTAssertEqual(currentMonth.count, 18)
    }

    func testCronaCalendarDateFormatsWireDateForLocale() {
        let formatted = CronaCalendarDate.localizedString(
            from: "2026-08-09",
            locale: Locale(identifier: "en_US")
        )

        XCTAssertNotNil(formatted)
        XCTAssertTrue(formatted?.contains("2026") == true)
        XCTAssertNil(CronaCalendarDate.localizedString(from: "not-a-date"))
    }

    func testPopoverStatsMessagesCoverKnownReasons() {
        XCTAssertTrue(PopoverStatsService.message(for: "no_activity").contains("Start"))
        XCTAssertTrue(PopoverStatsService.message(for: "under_target").contains("planned"))
        XCTAssertTrue(PopoverStatsService.message(for: "needs_breaks").contains("recovery"))
        XCTAssertTrue(PopoverStatsService.message(for: "overextended").contains("beyond"))
        XCTAssertEqual(PopoverStatsService.title(for: "no_activity"), "Ready to begin")
        XCTAssertEqual(PopoverStatsService.title(for: "needs_breaks"), "Take a break")
        XCTAssertFalse(PopoverStatsService.message(for: "unknown").isEmpty)
    }

    func testCronaCalendarDateQuickChoicesAreStable() throws {
        XCTAssertEqual(
            CronaCalendarDate.adding(days: 1, to: "2026-07-26"),
            "2026-07-27"
        )
        XCTAssertEqual(
            CronaCalendarDate.adding(days: 7, to: "2026-07-26"),
            "2026-08-02"
        )
        let date = try XCTUnwrap(CronaCalendarDate.date(from: "2026-08-02"))
        XCTAssertEqual(CronaCalendarDate.string(from: date), "2026-08-02")
    }
}
