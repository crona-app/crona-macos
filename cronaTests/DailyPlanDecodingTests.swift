import XCTest
@testable import crona

@MainActor
final class DailyPlanDecodingTests: XCTestCase {
    func testEmptyPlanAcceptsOmittedNullOrEmptyEntries() throws {
        for entries in ["", #", "entries": null"#, #", "entries": []"#] {
            let payload = """
                {"id":"plan", "date":"2026-11-17", "createdAt":"", "updatedAt":""\(entries)}
                """
            let plan = try JSONDecoder().decode(CronaDailyPlan.self, from: Data(payload.utf8))
            XCTAssertEqual(plan.date, "2026-11-17")
            XCTAssertTrue(plan.entries.isEmpty)
        }
    }

    func testInvalidEntriesStillFailDecoding() {
        let payload = #"{"id":"plan","date":"2026-11-17","createdAt":"","updatedAt":"","entries":"invalid"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(CronaDailyPlan.self, from: Data(payload.utf8)))
    }
}
