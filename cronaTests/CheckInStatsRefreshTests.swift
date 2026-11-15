import XCTest
@testable import crona

@MainActor
final class CheckInStatsRefreshTests: DaemonTestCase {
    func testHistoricalCheckInInvalidatesItsCalendarCacheWithoutChangingSelectedDay() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.libraryFixtures["dashboard.focus_score_range"] = [[
            "date": "2001-02-01", "score": 40, "level": "steady", "reason": "balanced", "hasData": true
        ]]
        let stats = PopoverStatsService(daemonConnection: connection)
        let selected = stats.snapshot.date
        await stats.prefetchCalendarDates(["2001-02-01"])
        XCTAssertNotNil(stats.cachedSnapshot(for: "2001-02-01"))
        let revision = stats.calendarCacheRevision
        await stats.checkInDidChange(date: "2001-02-01")
        XCTAssertNil(stats.cachedSnapshot(for: "2001-02-01"))
        XCTAssertEqual(stats.snapshot.date, selected)
        XCTAssertGreaterThan(stats.calendarCacheRevision, revision)
    }
}
