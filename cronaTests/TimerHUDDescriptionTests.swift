import XCTest
@testable import crona

@MainActor
final class TimerHUDDescriptionTests: DaemonTestCase {
    func testCachedIssueAvoidsAdditionalLookup() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = ["state": "running", "sessionId": "hud", "issueId": 42, "elapsedSeconds": 10]
        transport.todaySummaryIssuesFixture = [["id": 42, "streamId": 7, "title": "Cached", "status": "planned",
                                               "workedSeconds": 0, "pinnedDaily": true, "description": "Already loaded"]]
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await state.timerService.refresh()
        await state.dailyIssues.refresh()
        let before = transport.methods.filter { $0 == "issue.list_all" || $0 == "issue.list" }.count
        await state.timerHUDExpansion.loadDescription(state: state)
        XCTAssertEqual(state.timerHUDExpansion.issueDescription, "Already loaded")
        XCTAssertEqual(transport.methods.filter { $0 == "issue.list_all" || $0 == "issue.list" }.count, before)
    }

    func testMissingCachedIssueUsesStreamScopedLookup() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = ["state": "running", "sessionId": "hud", "issueId": 42, "elapsedSeconds": 10]
        transport.libraryFixtures["issue.list"] = [["id": 42, "streamId": 7, "title": "Focus", "status": "planned",
                                                    "workedSeconds": 0, "pinnedDaily": false, "description": "Scoped description"]]
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await settleAsyncTasks()
        await state.timerService.refresh()
        state.contextService.snapshot = ContextSnapshot(streamID: 7)
        let before = transport.methods.filter { $0 == "issue.list_all" }.count
        await state.timerHUDExpansion.loadDescription(state: state)
        XCTAssertEqual(state.timerHUDExpansion.issueDescription, "Scoped description")
        XCTAssertEqual(transport.requests.last { $0.method == "issue.list" }?.params["streamId"]?.intValue, 7)
        XCTAssertEqual(transport.methods.filter { $0 == "issue.list_all" }.count, before)
    }
}
