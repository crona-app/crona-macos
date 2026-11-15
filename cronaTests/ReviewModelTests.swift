import XCTest

@testable import crona

@MainActor
final class ReviewModelTests: DaemonTestCase {
    func testIndependentSectionsSurviveEndpointFailureAndRetry() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.libraryFixtures["metrics.range"] = [
            [
                "date": "2001-02-03", "workedSeconds": 3600, "restSeconds": 0,
                "sessionCount": 1, "totalIssues": 0, "completedIssues": 0, "abandonedIssues": 0,
                "totalEstimatedMinutes": 0,
                "habitDueCount": 0, "habitCompletedCount": 0, "habitFailedCount": 0,
            ]
        ]
        transport.libraryFixtures["dashboard.focus_score_range"] = [Any]()
        transport.libraryFixtures["dashboard.window"] =
            [
                "startDate": "2001-01-29", "endDate": "2001-02-03",
                "plannedCount": 0, "completedCount": 0, "failedCount": 0, "abandonedCount": 0, "missedCount": 0,
                "carryOverCount": 0,
            ] as [String: Any]
        transport.failedLibraryMethods = ["dashboard.goal_progress"]
        let model = ReviewModel(connection: connection, settings: { CronaCoreSettings(awayDates: ["2001-02-02"]) })
        await model.refresh()
        XCTAssertEqual(model.totalWork, 3600)
        XCTAssertEqual(model.averageWork, 600)
        XCTAssertEqual(model.totalSessions, 1)
        XCTAssertNotNil(model.errors["Estimates"])
        XCTAssertNil(model.completionDelta)
        XCTAssertTrue(model.isAway("2001-02-02"))
        XCTAssertFalse(model.isAway("2001-02-01"))
        transport.failedLibraryMethods = []
        transport.libraryFixtures["dashboard.goal_progress"] =
            [
                "totalEstimateMinutes": 0, "totalActualSeconds": 0,
                "estimatedItems": 0, "averageDeltaMinutes": 0, "averageDeltaPercent": 0, "estimateBias": "balanced",
            ] as [String: Any]
        await model.refresh(section: "Estimates")
        XCTAssertNil(model.errors["Estimates"])
        XCTAssertEqual(model.estimates?.estimatedItems, 0)
        XCTAssertEqual(model.totalWork, 3600)
    }
    func testSupersededReviewRangeCannotReplaceNewerSelection() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.checkInByDate = [transport.logicalDate: ["date": transport.logicalDate, "mood": 4, "energy": 3]]
        transport.suspendCheckInRange = true
        let model = ReviewModel(connection: connection, settings: { CronaCoreSettings() })
        let older = Task { await model.refresh() }
        await waitForIssueCreator { transport.methods.contains("checkin.range") }
        model.shift(-1)
        let newerRange = model.range
        transport.suspendCheckInRange = false
        await model.refresh()
        transport.resumeCheckInRange()
        await older.value
        XCTAssertEqual(model.loadedRange, newerRange)
        XCTAssertTrue(model.checkIns.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

}
