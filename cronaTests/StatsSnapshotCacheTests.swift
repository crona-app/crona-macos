import XCTest
@testable import crona

@MainActor
final class StatsSnapshotCacheTests: XCTestCase {
    func testOnlyThreeMonthsAndProtectedDatesAreRetained() {
        var cache = StatsSnapshotCache()
        cache.protectedDates = ["2000-01-01", "2000-02-01"]
        for month in 1...6 {
            for day in 1...28 {
                let date = String(format: "2000-%02d-%02d", month, day)
                cache[date] = PopoverStatsSnapshot(date: date)
            }
        }
        XCTAssertNotNil(cache["2000-01-01"])
        XCTAssertNotNil(cache["2000-02-01"])
        XCTAssertNil(cache["2000-01-02"])
        XCTAssertNil(cache["2000-03-01"])
        XCTAssertNotNil(cache["2000-06-28"])
        cache.removeAll()
        XCTAssertNil(cache["2000-01-01"])
    }

    func testRecentlyReadMonthSurvivesEviction() {
        var cache = StatsSnapshotCache()
        for month in 1...3 {
            let date = String(format: "2000-%02d-01", month)
            cache[date] = PopoverStatsSnapshot(date: date)
        }
        XCTAssertNotNil(cache["2000-01-01"])
        cache["2000-04-01"] = PopoverStatsSnapshot(date: "2000-04-01")
        XCTAssertNil(cache["2000-02-01"])
        XCTAssertNotNil(cache["2000-01-01"])
    }
}
