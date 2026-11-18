import XCTest
@testable import crona

@MainActor
final class PeekTests: DaemonTestCase {
    private let issue = DailyFocusIssue(id: 42, streamID: 7, title: "Peek work", status: "planned",
        estimateMinutes: 45, workedSeconds: 0, todoForDate: nil, repoName: "Crona", streamName: "Mac")

    func testPeekDraftsDoNotChangeMenuDraftsAndSurviveDismissal() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.issueCapture.text = "Menu draft"
        state.peek.capture.text = "Peek draft"
        state.peek.prepare(issue)
        state.peek.setup.countdown = "47m"
        state.peek.dismiss()
        XCTAssertEqual(state.issueCapture.text, "Menu draft")
        XCTAssertEqual(state.peek.capture.text, "Peek draft")
        XCTAssertEqual(state.peek.selectedIssue, issue)
        XCTAssertEqual(state.peek.setup.countdown, "47m")
        XCTAssertNil(state.selectedFocusIssue)
    }

    func testStartFailurePreservesSetupAndReportsError() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        transport.failStart = true
        state.peek.prepare(issue)
        await state.peek.start()
        XCTAssertNotNil(state.peek.error)
        XCTAssertTrue(state.peek.showsSetup)
        XCTAssertEqual(state.peek.selectedIssue, issue)
        XCTAssertFalse(state.peek.isStarting)
    }

    func testSuccessfulStartClearsOnlyPeekSetup() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.peek.prepare(issue)
        await state.peek.start()
        XCTAssertTrue(transport.methods.contains("timer.start"))
        XCTAssertFalse(state.peek.showsSetup)
        XCTAssertNil(state.peek.selectedIssue)
        XCTAssertNil(state.selectedFocusIssue)
    }

    func testConflictingMenuSetupPreventsStart() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.beginAdhocStart()
        state.peek.prepare(issue)
        await state.peek.start()
        XCTAssertFalse(transport.methods.contains("timer.start"))
        XCTAssertNotNil(state.peek.error)
        XCTAssertTrue(state.isAdhocStartSelected)
    }

    func testCaptureFailurePreservesDraftAndSuccessClearsIt() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        transport.captureProposalsFixture = [["line": 1, "title": "Peek draft", "inbox": true]]
        state.peek.capture.text = "Peek draft"
        await state.peek.capture.parseNow()
        XCTAssertTrue(state.peek.capture.canImport)
        transport.failCaptureImport = true
        await state.peek.importCapture()
        XCTAssertEqual(state.peek.capture.text, "Peek draft")
        XCTAssertNotNil(state.peek.capture.errorMessage)
        transport.failCaptureImport = false
        await state.peek.importCapture()
        XCTAssertEqual(state.peek.capture.text, "")
        XCTAssertEqual(transport.lastImportProposalCount, 1)
    }

    func testRepeatedStartWhileRequestIsPendingIsIgnored() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        transport.suspendStart = true
        state.peek.prepare(issue)
        let first = Task { await state.peek.start() }
        await waitForIssueCreator { state.peek.isStarting }
        await state.peek.start()
        transport.resumeStart()
        await first.value
        XCTAssertEqual(transport.methods.filter { $0 == "timer.start" }.count, 1)
    }

    func testPeekRefreshDoesNotChangeSelectedDatesElsewhere() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.popoverStatsService.selectDate("2000-01-01")
        await state.peek.refresh()
        XCTAssertEqual(state.popoverStatsService.functionalDate, "2000-01-01")
        XCTAssertEqual(state.peek.daily.snapshot.date, connection.currentDate)
    }
    func testHistoricalDayBlocksStartAndCaptureWithoutDestroyingDrafts() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.peek.prepare(issue)
        state.peek.capture.text = "Keep this draft"
        state.peek.day.select("2000-01-01")
        await state.peek.start()
        await state.peek.importCapture()
        XCTAssertFalse(transport.methods.contains("timer.start"))
        XCTAssertFalse(transport.methods.contains("issue.capture.import"))
        XCTAssertEqual(state.peek.capture.text, "Keep this draft")
        XCTAssertEqual(state.peek.selectedIssue, issue)
    }

    func testCalendarSelectionRefreshesEveryPeekPaneAndClearsPreview() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.peek.previewIssue = issue
        state.peek.day.select("2000-01-01")
        XCTAssertNil(state.peek.previewIssue)
        await state.peek.refresh()
        XCTAssertEqual(state.peek.habits.snapshot.date, "2000-01-01")
        XCTAssertEqual(state.peek.stats.functionalDate, "2000-01-01")
        XCTAssertEqual(state.peek.issues.loadedDate, "2000-01-01")
        XCTAssertNotEqual(state.day.selectedDate, "2000-01-01")
    }

}
