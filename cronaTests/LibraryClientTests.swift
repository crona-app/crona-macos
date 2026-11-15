import XCTest

@testable import crona

@MainActor
final class LibraryClientTests: XCTestCase {
    func testHistoryMethodsUseCoreWireNamesAndDateParameters() async throws {
        let transport = CapturingDaemonTransport(responseData: Data(#"{"id":"r","result":[]}"#.utf8))
        let client = CronaDaemonClient(transport: transport)
        _ = try await client.checkInRange()
        var request = try probe(transport)
        XCTAssertEqual(request.method, "checkin.range")
        XCTAssertEqual(request.params["start"]?.stringValue, "0001-01-01")
        XCTAssertEqual(request.params["end"]?.stringValue, "9999-12-31")
        _ = try await client.habitHistory()
        let object = try JSONSerialization.jsonObject(with: XCTUnwrap(transport.requestData)) as! [String: Any]
        XCTAssertEqual(object["method"] as? String, "habit.history")
        _ = try await client.operations(since: "2026-11-15T00:00:00Z")
        request = try probe(transport)
        XCTAssertEqual(request.method, "ops.since")
        XCTAssertEqual(request.params["since"]?.stringValue, "2026-11-15T00:00:00Z")
    }

    func testPlanAndEstimateResponsesDecodeCoreAggregates() async throws {
        let planTransport = CapturingDaemonTransport(
            responseData: Data(
                #"{"id":"r","result":{"startDate":"2026-11-01","endDate":"2026-11-15","plannedCount":4,"completedCount":3,"failedCount":1,"abandonedCount":0,"missedCount":1,"carryOverCount":2,"accountabilityScore":75,"days":[{"date":"2026-11-01","plannedCount":2,"completedCount":2}]}}"#
                    .utf8))
        let plan = try await CronaDaemonClient(transport: planTransport).planWindow(
            start: "2026-11-01", end: "2026-11-15")
        XCTAssertEqual(plan.completionRate, 0.75)
        XCTAssertEqual(plan.fullyCompletedDays, 1)
        XCTAssertEqual(try probe(planTransport).method, "dashboard.window")
        let estimatesTransport = CapturingDaemonTransport(
            responseData: Data(
                #"{"id":"r","result":{"totalEstimateMinutes":60,"totalActualSeconds":4200,"estimatedItems":1,"averageDeltaMinutes":10,"averageDeltaPercent":16.7,"estimateBias":"underestimated"}}"#
                    .utf8))
        let estimates = try await CronaDaemonClient(transport: estimatesTransport).estimateSummary(
            start: "2026-11-01", end: "2026-11-15")
        XCTAssertEqual(estimates.deltaSeconds, 600)
        let request = try probe(estimatesTransport)
        XCTAssertEqual(request.method, "dashboard.goal_progress")
        XCTAssertEqual(request.params["groupBy"]?.stringValue, "issue")
        XCTAssertNil(request.params["repoId"])
    }

    func testCheckInDeleteAndOptionalHistoryFields() async throws {
        let transport = CapturingDaemonTransport(responseData: Data(#"{"id":"r","result":{"ok":true}}"#.utf8))
        _ = try await CronaDaemonClient(transport: transport).checkInDelete(date: "2026-11-15")
        XCTAssertEqual(try probe(transport).method, "checkin.delete")
        XCTAssertEqual(try probe(transport).params["date"]?.stringValue, "2026-11-15")
        let history = try JSONDecoder().decode(
            [CronaHabitCompletion].self,
            from: Data(#"[{"id":1,"habitId":2,"date":"2026-11-15","status":"completed"}]"#.utf8))
        XCTAssertNil(history.first?.durationMinutes)
        let settings = try JSONDecoder().decode(CronaCoreSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.weekStart, "monday")
    }

    private func probe(_ transport: CapturingDaemonTransport) throws -> RequestWithParamsProbe {
        try JSONDecoder().decode(RequestWithParamsProbe.self, from: XCTUnwrap(transport.requestData))
    }
}
