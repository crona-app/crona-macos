import XCTest

@testable import crona

@MainActor
final class DailyStatsPresentationTests: XCTestCase {
    func testFocusShareAndAverageRemainDistinctFromScore() {
        let stats = presentation(work: 3600, rest: 1200, sessions: 2, target: 7200)
        XCTAssertEqual(stats.focusFraction, 0.75)
        XCTAssertEqual(stats.score.score, 22)
        XCTAssertEqual(stats.workedFraction, 0.5)
        XCTAssertEqual(stats.averageSessionSeconds, 1800)
        XCTAssertEqual(stats.remainingSeconds, 3600)
    }

    func testEmptyDayDoesNotInventFocusShareOrSessionAverage() {
        let stats = presentation(work: 0, rest: 0, sessions: 0, target: 0)
        XCTAssertNil(stats.focusFraction)
        XCTAssertNil(stats.averageSessionSeconds)
        XCTAssertEqual(stats.workedFraction, 0)
        XCTAssertEqual(stats.issuesFraction, 0)
        XCTAssertEqual(stats.habitsFraction, 0)
    }

    func testTargetOverrunHasNoNegativeTimeRemaining() {
        let stats = presentation(work: 5400, rest: 0, sessions: 1, target: 3600)
        XCTAssertEqual(stats.workedFraction, 1.5)
        XCTAssertEqual(stats.remainingSeconds, 0)
        XCTAssertEqual(stats.focusFraction, 1)
    }

    private func presentation(work: Int, rest: Int, sessions: Int, target: Int) -> DailyStatsPresentation {
        let score = CronaFocusScoreSummary(
            startDate: "2026-11-15", endDate: "2026-11-15", score: 22, level: "low",
            workedSeconds: work, restSeconds: rest, sessionCount: sessions, focusDays: 1,
            days: 1, targetWorkedSeconds: target)
        let metrics = CronaDailyMetricsDay(
            date: "2026-11-15", workedSeconds: work, restSeconds: rest, sessionCount: sessions,
            totalIssues: 0, completedIssues: 0, abandonedIssues: 0, totalEstimatedMinutes: 0,
            habitDueCount: 0, habitCompletedCount: 0, habitFailedCount: 0)
        return DailyStatsPresentation(score: score, metrics: metrics)
    }
}
