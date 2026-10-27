import XCTest
@testable import crona

@MainActor
final class IssueCreatorModelTests: DaemonTestCase {
    private let fixtureIssue = DailyFocusIssue(id: 42, streamID: 7, title: "Fixture", status: "planned",
        estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)

    func testIssueCreatorDoesNotOpenWhileEndSessionSheetIsPresented() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.endSession.isSheetPresented = true

        appState.issueCreator.presentCreator()

        XCTAssertFalse(appState.issueCreator.isPresented)
    }

    func testIssueCreatorDoesNotOpenWhileIssueActionEditorIsPresented() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueActions.editor = .delete(issue: fixtureIssue)

        appState.issueCreator.presentCreator()

        XCTAssertFalse(appState.issueCreator.isPresented)
    }

    func testIssueCreatorIgnoresReopenUntilDismissalCompletes() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)

        appState.issueCreator.presentCreator()
        appState.issueCreator.cancel()
        appState.issueCreator.presentCreator()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(appState.issueCreator.isPresented)

        appState.issueCreator.presentCreator()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(appState.issueCreator.isPresented)
        XCTAssertTrue(appState.issueCreator.isContentVisible)
    }

    func testIssueEditorPreservesAndClearsOptionalScheduling() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        let issue = DailyFocusIssue(id: 42, streamID: 7, title: "Original", status: "planned",
            estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)
        appState.issueCreator.presentEditor(for: issue)
        XCTAssertNil(appState.issueCreator.dueDate)
        appState.issueCreator.title = "Edited"
        appState.issueCreator.submit()
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertEqual(transport.methods.filter { $0 == "issue.update" }.count, 1)
        XCTAssertFalse(transport.methods.contains("issue.set_todo"))
        XCTAssertFalse(transport.methods.contains("issue.clear_todo"))

        let scheduled = DailyFocusIssue(id: 42, streamID: 7, title: "Scheduled", status: "planned",
            estimateMinutes: nil, workedSeconds: 0, todoForDate: transport.logicalDate)
        appState.issueCreator.presentEditor(for: scheduled)
        XCTAssertEqual(appState.issueCreator.dueDate.map(CronaCalendarDate.string(from:)), transport.logicalDate)
        appState.issueCreator.dueDate = nil
        appState.issueCreator.submit()
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertEqual(transport.methods.filter { $0 == "issue.clear_todo" }.count, 1)
    }

    func testIssueEditorOnlyWritesChangedScheduling() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let service = IssueActionsService(daemonConnection: connection,
            dailyFocusService: DailyFocusService(daemonConnection: connection))
        let issue = DailyFocusIssue(id: 42, streamID: 7, title: "Original", status: "planned",
            estimateMinutes: nil, workedSeconds: 0, todoForDate: transport.logicalDate)
        let unchanged = await service.updateIssue(issue: issue, title: "Edited", description: nil,
            estimateMinutes: 30, todoForDate: transport.logicalDate)
        XCTAssertTrue(unchanged)
        XCTAssertFalse(transport.methods.contains("issue.set_todo"))
        let changed = await service.updateIssue(issue: issue, title: "Edited", description: nil,
            estimateMinutes: 30, todoForDate: "2001-02-04")
        XCTAssertTrue(changed)
        XCTAssertEqual(transport.requests.last { $0.method == "issue.set_todo" }?.params["date"]?.stringValue,
            "2001-02-04")
    }

    func testIssueCreatorDefaultsAndSuccessUseDaemonLogicalDate() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueCreator.presentCreator()
        XCTAssertNotEqual(transport.logicalDate, DailyFocusService.todayString())
        XCTAssertEqual(appState.issueCreator.dueDate.map(CronaCalendarDate.string(from:)), transport.logicalDate)
        appState.issueCreator.title = "New"
        appState.issueCreator.destinationID = 7
        appState.issueCreator.submit()
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertEqual(transport.requests.last { $0.method == "issue.create" }?.params["todoForDate"]?.stringValue,
            transport.logicalDate)
        XCTAssertEqual(appState.issueCreator.success?.plannedForToday, true)

        appState.issueCreator.presentCreator()
        appState.issueCreator.title = "Unscheduled"
        appState.issueCreator.destinationID = 7
        appState.issueCreator.dueDate = nil
        appState.issueCreator.submit()
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertNil(transport.requests.last { $0.method == "issue.create" }?.params["todoForDate"])
        XCTAssertEqual(appState.issueCreator.success?.plannedForToday, false)
    }

    func testIssueCreatorLocksSubmissionThroughRefreshAndCreateMore() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueCreator.presentCreator()
        await settleAsyncTasks()
        appState.issueCreator.title = "New"
        appState.issueCreator.destinationID = 7
        appState.issueCreator.dueDate = CronaCalendarDate.date(from: "2001-02-04")
        transport.suspendRefresh = true
        appState.issueCreator.submit(followUp: .more)
        XCTAssertTrue(appState.issueCreator.isSubmitting)
        appState.issueCreator.submit(followUp: .more)
        await waitForIssueCreator { transport.refreshContinuation != nil }
        XCTAssertFalse(appState.issueCreationService.isCreating)
        XCTAssertTrue(appState.issueCreator.isSubmitting)
        appState.issueCreator.submit(followUp: .more)
        appState.issueCreator.cancel()
        XCTAssertTrue(appState.issueCreator.isPresented)
        XCTAssertEqual(appState.issueCreator.title, "New")
        XCTAssertEqual(transport.methods.filter { $0 == "issue.create" }.count, 1)
        transport.resumeRefresh()
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertEqual(appState.issueCreator.title, "")
        XCTAssertEqual(appState.issueCreator.destinationID, 7)
        XCTAssertEqual(appState.issueCreator.dueDate.map(CronaCalendarDate.string(from:)), "2001-02-04")
    }

    func testIssueCreatorFailureReleasesSubmissionAndRetainsInputs() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueCreator.title = "Retry me"
        appState.issueCreator.destinationID = 7
        transport.failCreation = true
        appState.issueCreator.submit()
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertEqual(appState.issueCreator.title, "Retry me")
        XCTAssertNotNil(appState.issueCreationService.lastErrorMessage)
        transport.failCreation = false
        appState.issueCreator.submit(followUp: .more)
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertEqual(transport.methods.filter { $0 == "issue.create" }.count, 2)
    }

    func testIssueCreatorKeepsSubmissionLockedDuringDismissal() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueCreator.presentCreator()
        await settleAsyncTasks()
        appState.issueCreator.title = "New"
        appState.issueCreator.destinationID = 7
        transport.suspendRefresh = true
        appState.issueCreator.submit()
        await waitForIssueCreator { transport.refreshContinuation != nil }
        transport.resumeRefresh()
        await waitForIssueCreator { appState.issueCreator.success != nil }
        XCTAssertTrue(appState.issueCreator.isSubmitting)
        XCTAssertTrue(appState.issueCreator.isPresented)
        appState.issueCreator.submit()
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertFalse(appState.issueCreator.isPresented)
        XCTAssertEqual(transport.methods.filter { $0 == "issue.create" }.count, 1)
    }

    func testIssueCreatorFallsBackWhenDaemonLogicalDateIsInvalid() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        _ = connection.applyDayBoundary(CronaDayBoundaryEventPayload(kind: "start",
            dateBefore: "", dateAfter: "", effectiveLocalTime: "", effectiveUTCTime: nil,
            timezone: "Asia/Kolkata", occurrenceID: "invalid", logicalDate: "2001-13-40"))
        XCTAssertEqual(CronaCalendarDate.string(from: appState.issueCreator.defaultDueDate), DailyFocusService.todayString())
    }

    func testIssueCreatorFocusGuardsActiveAndNewlyStartedSessions() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueCreator.title = "New"
        appState.issueCreator.destinationID = 7
        appState.timerService.snapshot = TimerSnapshot(state: "running", sessionID: "active")
        appState.issueCreator.submit(followUp: .focus)
        XCTAssertFalse(appState.issueCreator.isSubmitting)
        XCTAssertFalse(transport.methods.contains("issue.create"))

        appState.timerService.snapshot = TimerSnapshot(state: "idle")
        transport.suspendRefresh = true
        appState.issueCreator.submit(followUp: .focus)
        await waitForIssueCreator { transport.refreshContinuation != nil }
        appState.timerService.snapshot = TimerSnapshot(state: "running", sessionID: "active")
        transport.resumeRefresh()
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertNil(appState.selectedFocusIssue)
        XCTAssertNotNil(appState.issueCreator.success)
        XCTAssertEqual(appState.timerService.snapshot.sessionID, "active")

        appState.timerService.snapshot = TimerSnapshot(state: "idle")
        appState.issueCreator.submit(followUp: .focus)
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }
        XCTAssertEqual(appState.selectedFocusIssue?.id, 42)
    }

    func testIssueCreatorSendsTags() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueCreator.presentCreator()
        await settleAsyncTasks()
        appState.issueCreator.title = "Tagged"
        appState.issueCreator.destinationID = 7
        appState.issueCreator.tags = ["work", "deep-work"]

        appState.issueCreator.submit(followUp: .more)
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }

        let create = try XCTUnwrap(transport.requests.first { $0.method == "issue.create" })
        XCTAssertEqual(create.params["tags"]?.stringArrayValue, ["work", "deep-work"])
        XCTAssertEqual(appState.issueCreator.tags, [])
    }

    func testIssueCreatorOmitsEmptyTags() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueCreator.presentCreator()
        await settleAsyncTasks()
        appState.issueCreator.title = "Plain"
        appState.issueCreator.destinationID = 7

        appState.issueCreator.submit(followUp: .more)
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }

        let create = try XCTUnwrap(transport.requests.first { $0.method == "issue.create" })
        XCTAssertNil(create.params["tags"])
    }

    func testIssueCreatorSendsPendingTagDraft() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueCreator.presentCreator()
        await settleAsyncTasks()
        appState.issueCreator.title = "Tagged"
        appState.issueCreator.destinationID = 7
        appState.issueCreator.tagDraft = "urgent"

        appState.issueCreator.submit(followUp: .more)
        await waitForIssueCreator { !appState.issueCreator.isSubmitting }

        let create = try XCTUnwrap(transport.requests.first { $0.method == "issue.create" })
        XCTAssertEqual(create.params["tags"]?.stringArrayValue, ["urgent"])
        XCTAssertEqual(appState.issueCreator.tagDraft, "")
    }
}
