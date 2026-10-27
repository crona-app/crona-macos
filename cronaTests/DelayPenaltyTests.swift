import XCTest
@testable import crona

@MainActor
final class DelayPenaltyTests: DaemonTestCase {
    private func planEntryJSON(penalty: String?) -> Data {
        let penaltyField = penalty.map { #","penalty":\#($0)"# } ?? ""
        let json = #"{"id":"e","date":"2026-10-27","issueId":1,"source":"todo_for_date","status":"planned","committedAt":"","baselineDate":"2026-10-25","currentPlannedDate":"2026-10-27","postponeCount":2,"currentDelayedDays":2,"maxDelayedDays":2,"failScore":3.1"#
            + penaltyField + "}"
        return Data(json.utf8)
    }

    func testPlanEntryDecodesPenalty() throws {
        let data = planEntryJSON(
            penalty: #"{"highRisk":true,"highRiskThreshold":2.5,"delayComponent":1.2,"ifPostponedOneDay":{"failScore":3.6,"accountabilityDelta":0.4,"becomesHighRisk":true}}"#)
        let entry = try JSONDecoder().decode(CronaDailyPlanEntry.self, from: data)
        XCTAssertEqual(entry.penalty?.highRisk, true)
        XCTAssertEqual(entry.penalty?.highRiskThreshold, 2.5)
        XCTAssertEqual(entry.penalty?.ifPostponedOneDay?.becomesHighRisk, true)
    }

    func testPlanEntryWithoutPenaltyDecodesNil() throws {
        let missing = try JSONDecoder().decode(CronaDailyPlanEntry.self, from: planEntryJSON(penalty: nil))
        XCTAssertNil(missing.penalty)
        let null = try JSONDecoder().decode(CronaDailyPlanEntry.self, from: planEntryJSON(penalty: "null"))
        XCTAssertNil(null.penalty)
    }
}
