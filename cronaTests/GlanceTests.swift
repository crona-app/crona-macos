import XCTest
@testable import crona

@MainActor
final class GlanceTests: DaemonTestCase {
    private let issue = DailyFocusIssue(id: 42, streamID: 7, title: "Glance work", status: "planned",
        estimateMinutes: 45, workedSeconds: 0, todoForDate: nil, repoName: "Crona", streamName: "Mac")

    func testGlanceDraftsDoNotChangeMenuDraftsAndSurviveDismissal() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.issueCapture.text = "Menu draft"
        state.glance.capture.text = "Glance draft"
        state.glance.prepare(issue)
        state.glance.setup.countdown = "47m"
        state.glance.dismiss()
        XCTAssertEqual(state.issueCapture.text, "Menu draft")
        XCTAssertEqual(state.glance.capture.text, "Glance draft")
        XCTAssertEqual(state.glance.selectedIssue, issue)
        XCTAssertEqual(state.glance.setup.countdown, "47m")
        XCTAssertNil(state.selectedFocusIssue)
    }

    func testStartFailurePreservesSetupAndReportsError() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        transport.failStart = true
        state.glance.prepare(issue)
        await state.glance.start()
        XCTAssertNotNil(state.glance.error)
        XCTAssertTrue(state.glance.showsSetup)
        XCTAssertEqual(state.glance.selectedIssue, issue)
        XCTAssertFalse(state.glance.isStarting)
    }

    func testSuccessfulStartClearsOnlyGlanceSetup() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.glance.prepare(issue)
        await state.glance.start()
        XCTAssertTrue(transport.methods.contains("timer.start"))
        XCTAssertFalse(state.glance.showsSetup)
        XCTAssertNil(state.glance.selectedIssue)
        XCTAssertNil(state.selectedFocusIssue)
    }

    func testConflictingMenuSetupPreventsStart() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.beginAdhocStart()
        state.glance.prepare(issue)
        await state.glance.start()
        XCTAssertFalse(transport.methods.contains("timer.start"))
        XCTAssertNotNil(state.glance.error)
        XCTAssertTrue(state.isAdhocStartSelected)
    }

    func testCaptureFailurePreservesDraftAndSuccessClearsIt() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        transport.captureProposalsFixture = [["line": 1, "title": "Glance draft", "inbox": true]]
        state.glance.capture.text = "Glance draft"
        await state.glance.capture.parseNow()
        XCTAssertTrue(state.glance.capture.canImport)
        transport.failCaptureImport = true
        await state.glance.importCapture()
        XCTAssertEqual(state.glance.capture.text, "Glance draft")
        XCTAssertNotNil(state.glance.capture.errorMessage)
        transport.failCaptureImport = false
        await state.glance.importCapture()
        XCTAssertEqual(state.glance.capture.text, "")
        XCTAssertEqual(transport.lastImportProposalCount, 1)
    }

    func testRepeatedStartWhileRequestIsPendingIsIgnored() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        transport.suspendStart = true
        state.glance.prepare(issue)
        let first = Task { await state.glance.start() }
        await waitForIssueCreator { state.glance.isStarting }
        await state.glance.start()
        transport.resumeStart()
        await first.value
        XCTAssertEqual(transport.methods.filter { $0 == "timer.start" }.count, 1)
    }

    func testGlanceRefreshDoesNotChangeSelectedDatesElsewhere() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.popoverStatsService.selectDate("2000-01-01")
        await state.glance.refresh()
        XCTAssertEqual(state.popoverStatsService.functionalDate, "2000-01-01")
        XCTAssertEqual(state.glance.daily.snapshot.date, connection.currentDate)
    }
    func testHistoricalDayBlocksStartAndCaptureWithoutDestroyingDrafts() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.glance.prepare(issue)
        state.glance.capture.text = "Keep this draft"
        state.glance.day.select("2000-01-01")
        await state.glance.start()
        await state.glance.importCapture()
        XCTAssertFalse(transport.methods.contains("timer.start"))
        XCTAssertFalse(transport.methods.contains("issue.capture.import"))
        XCTAssertEqual(state.glance.capture.text, "Keep this draft")
        XCTAssertEqual(state.glance.selectedIssue, issue)
    }

    func testCalendarSelectionRefreshesEveryGlancePaneAndClearsPreview() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.glance.previewIssue = issue
        state.glance.day.select("2000-01-01")
        XCTAssertNil(state.glance.previewIssue)
        await state.glance.refresh()
        XCTAssertEqual(state.glance.habits.snapshot.date, "2000-01-01")
        XCTAssertEqual(state.glance.stats.functionalDate, "2000-01-01")
        XCTAssertEqual(state.glance.issues.loadedDate, "2000-01-01")
        XCTAssertNotEqual(state.day.selectedDate, "2000-01-01")
    }

}
