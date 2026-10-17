import XCTest
@testable import crona

@MainActor
final class AdhocSessionTests: DaemonTestCase {
    func testAdhocStartRequestsKeepContextUnsetInEveryMode() throws {
        for mode in [FocusSessionMode.stopwatch, .timer, .pomodoro] {
            var config = FocusStartConfigState.defaultState(estimateMinutes: nil, workedSeconds: 0)
            config.mode = mode
            let request = config.startRequest(for: nil)
            XCTAssertEqual(request.adhoc, true)
            XCTAssertNil(request.issueID)
            XCTAssertNil(request.repoID)
            XCTAssertNil(request.streamID)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
            XCTAssertEqual(object["adhoc"] as? Bool, true)
            XCTAssertNil(object["issueId"])
            if mode == .timer { XCTAssertEqual(request.hardLimitKind, .countdown) }
            if mode == .pomodoro { XCTAssertEqual(request.hardLimitKind, .pomodoro) }
        }
    }

    func testAdhocTimerDecodingAndAttributionWireFields() throws {
        let ordinary = try JSONDecoder().decode(CronaTimerState.self, from: Data(#"{"state":"idle"}"#.utf8))
        XCTAssertFalse(TimerSnapshot.from(ordinary).adhoc)
        let adhoc = try JSONDecoder().decode(CronaTimerState.self, from: Data(#"{"state":"running","adhoc":true,"sessionId":"s"}"#.utf8))
        XCTAssertTrue(TimerSnapshot.from(adhoc).adhoc)
        let request = CronaEndSessionRequest(commitMessage: "Work", adhocResolution: .attach, issueID: 42)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(object["adhocResolution"] as? String, "attach")
        XCTAssertEqual(object["issueId"] as? Int, 42)
        XCTAssertEqual(object["commitMessage"] as? String, "Work")
        XCTAssertNil(object["newIssueTitle"])
        XCTAssertEqual(CronaProtocolVersion.current.rawValue, "1.6")
    }

    func testAdhocPickerFiltersEligibilityAndLogicalDate() throws {
        func issue(_ id: Int64, status: String, date: String?, pinned: Bool = false) -> CronaIssue {
            CronaIssue(id: id, streamID: 7, title: "Issue", status: status, estimateMinutes: nil,
                workedSeconds: 0, pinnedDaily: pinned, todoForDate: date)
        }
        var state = AdhocAttributionState.initial(elapsedSeconds: 901, date: "2001-02-03", streamID: 7)
        XCTAssertEqual(state.estimateMinutes, 30)
        XCTAssertEqual(state.date, "2001-02-03")
        state.issues = [issue(1, status: "planned", date: state.date),
            issue(2, status: "ready", date: "2001-02-02"),
            issue(3, status: "in_progress", date: nil, pinned: true),
            issue(4, status: "done", date: state.date), issue(5, status: "blocked", date: state.date)]
        XCTAssertEqual(state.filteredIssues(today: state.date).map(\.id), [1])
        state.filter = .overdue
        XCTAssertEqual(state.filteredIssues(today: state.date).map(\.id), [2])
        state.filter = .pinned
        XCTAssertEqual(state.filteredIssues(today: state.date).map(\.id), [3])
        state.filter = .all
        XCTAssertEqual(state.filteredIssues(today: state.date).map(\.id), [1, 2, 3])
    }

    func testAdhocCreateRetriesCompletionWithoutCreatingAgain() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        transport.provideDestinations = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)
        await appState.endSession.loadAdhocAttribution()
        XCTAssertEqual(appState.endSession.adhocAttribution.date, transport.logicalDate)
        appState.endSession.adhocAttribution.resolution = .create
        appState.endSession.adhocAttribution.destinationID = 7
        appState.endSession.adhocAttribution.title = "Created work"
        appState.endSession.commitMessage = "Summary"
        transport.failEnd = true
        appState.endSession.confirm()
        appState.endSession.confirm()
        await waitForIssueCreator { !appState.endSession.isSubmitting }
        XCTAssertEqual(transport.methods.filter { $0 == "issue.create" }.count, 1)
        XCTAssertEqual(transport.methods.filter { $0 == "timer.end" }.count, 1)
        XCTAssertEqual(appState.endSession.adhocAttribution.createdIssue?.id, 42)
        XCTAssertNotNil(appState.endSession.errorMessage)
        appState.endSession.cancel()
        appState.endSession.begin(source: .menuPopover)
        XCTAssertEqual(appState.endSession.adhocAttribution.createdIssue?.id, 42)
        XCTAssertEqual(appState.endSession.commitMessage, "Summary")
        transport.failEnd = false
        appState.endSession.confirm()
        await waitForIssueCreator { transport.methods.filter { $0 == "timer.end" }.count == 2 }
        XCTAssertEqual(transport.methods.filter { $0 == "issue.create" }.count, 1)
        let end = try XCTUnwrap(transport.requests.last(where: { $0.method == "timer.end" }))
        XCTAssertEqual(end.params["adhocResolution"]?.stringValue, "attach")
    }

    func testAdhocCompletionRejectsMissingSummaryAndDestination() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)
        appState.endSession.adhocAttribution.resolution = .keep
        let previousFocusRequest = appState.endSession.focusRequest
        appState.endSession.confirm()
        XCTAssertNotNil(appState.endSession.errorMessage)
        XCTAssertGreaterThan(appState.endSession.focusRequest, previousFocusRequest)
        appState.endSession.commitMessage = "Summary"
        appState.endSession.adhocAttribution.resolution = .attach
        appState.endSession.confirm()
        XCTAssertFalse(transport.methods.contains("timer.end"))
        appState.timerService.snapshot.sessionID = "another-session"
        appState.endSession.confirm()
        XCTAssertTrue(appState.endSession.errorMessage?.contains("changed") == true)
    }

    func testAdhocKeepCompletionUsesKeepResolution() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)
        XCTAssertFalse(appState.endSession.canSubmit)
        appState.endSession.adhocAttribution.resolution = .keep
        appState.endSession.commitMessage = "Kept work"
        XCTAssertTrue(appState.endSession.canSubmit)
        appState.endSession.confirm()
        await waitForIssueCreator { transport.methods.contains("timer.end") }
        let request = try XCTUnwrap(transport.requests.first(where: { $0.method == "timer.end" }))
        XCTAssertEqual(request.params["adhocResolution"]?.stringValue, "keep")
        XCTAssertFalse(transport.methods.contains("issue.create"))
    }

    func testAdhocDraftResetsWhenSessionChanges() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)
        appState.endSession.adhocAttribution.resolution = .create
        appState.endSession.adhocAttribution.title = "Old draft"
        appState.endSession.commitMessage = "Old summary"
        appState.endSession.cancel()
        appState.timerService.snapshot.sessionID = "new-session"
        appState.endSession.begin(source: .timerHUD)
        XCTAssertNil(appState.endSession.adhocAttribution.resolution)
        XCTAssertEqual(appState.endSession.adhocAttribution.title, "")
        XCTAssertEqual(appState.endSession.commitMessage, "")
    }

    func testInvalidAdhocEstimateOnlyBlocksIssueCreation() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)
        appState.endSession.adhocAttribution.estimateMinutes = -1
        appState.endSession.adhocAttribution.resolution = .create
        XCTAssertFalse(appState.endSession.canSubmit)
        appState.endSession.adhocAttribution.resolution = .keep
        XCTAssertTrue(appState.endSession.canSubmit)
        appState.endSession.adhocAttribution.resolution = .attach
        XCTAssertTrue(appState.endSession.canSubmit)
    }

    func testUnscheduledAdhocIssueIsPreparedAndRetainedAcrossRetry() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        transport.provideDestinations = true
        transport.creationStatus = "backlog"
        transport.failStatusChange = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)
        await appState.endSession.loadAdhocAttribution()
        appState.endSession.adhocAttribution.resolution = .create
        appState.endSession.adhocAttribution.destinationID = 7
        appState.endSession.adhocAttribution.title = "Unscheduled work"
        appState.endSession.adhocAttribution.date = ""
        appState.endSession.commitMessage = "Summary"
        appState.endSession.confirm()
        await waitForIssueCreator { !appState.endSession.isSubmitting }
        XCTAssertEqual(appState.endSession.adhocAttribution.createdIssue?.status, "backlog")
        XCTAssertFalse(transport.methods.contains("timer.end"))
        transport.failStatusChange = false
        appState.endSession.confirm()
        await waitForIssueCreator { transport.methods.contains("timer.end") }
        XCTAssertEqual(transport.methods.filter { $0 == "issue.create" }.count, 1)
        XCTAssertEqual(appState.endSession.adhocAttribution.createdIssue?.status, "ready")
        let creation = try XCTUnwrap(transport.requests.first(where: { $0.method == "issue.create" }))
        XCTAssertNil(creation.params["todoForDate"]?.stringValue)
        let status = try XCTUnwrap(transport.requests.last(where: { $0.method == "issue.change_status" }))
        XCTAssertEqual(status.params["status"]?.stringValue, "ready")
    }
}
