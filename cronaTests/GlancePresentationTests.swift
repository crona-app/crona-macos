import XCTest
@testable import crona

@MainActor
final class GlancePresentationTests: DaemonTestCase {
    func testStartSuccessKeepsGlancePresented() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        let window = TestGlanceWindow()
        let glance = GlanceModel(appState: state, window: window)
        glance.toggle(appState: state)
        glance.prepare()
        await glance.start()
        XCTAssertTrue(glance.isPresented)
        XCTAssertFalse(glance.showsSetup)
        XCTAssertEqual(window.dismissals, 0)
        glance.dismiss()
    }

    func testCaptureSuccessClosesOnlyCaptureCard() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        let window = TestGlanceWindow()
        let glance = GlanceModel(appState: state, window: window)
        glance.toggle(appState: state)
        glance.toggleCapture()
        transport.captureProposalsFixture = [["line": 1, "title": "Draft", "inbox": true]]
        glance.capture.text = "Draft"
        await glance.capture.parseNow()
        await glance.importCapture()
        XCTAssertTrue(glance.isPresented)
        XCTAssertFalse(glance.showsCapture)
        XCTAssertEqual(window.dismissals, 0)
        glance.dismiss()
    }

    func testEscapeClosesCardBeforeGlance() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        let window = TestGlanceWindow()
        let glance = GlanceModel(appState: state, window: window)
        glance.toggle(appState: state)
        glance.prepare()
        glance.handleEscape()
        XCTAssertTrue(glance.isPresented)
        XCTAssertFalse(glance.showsSetup)
        glance.handleEscape()
        XCTAssertFalse(glance.isPresented)
        XCTAssertEqual(window.dismissals, 1)
    }

    func testSharedCreatorDraftSurvivesOpeningGlance() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.issueCreator.presentCreator()
        state.issueCreator.title = "Keep this shared draft"
        let glance = GlanceModel(appState: state, window: TestGlanceWindow())
        glance.toggle(appState: state)
        XCTAssertTrue(state.issueCreator.isPresented)
        XCTAssertEqual(state.issueCreator.title, "Keep this shared draft")
        glance.dismiss()
        XCTAssertEqual(state.issueCreator.title, "Keep this shared draft")
    }
    func testHabitLogUsesPresentationServiceDateRatherThanPopupDate() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        state.habitsService.selectedDate = "2000-01-01"
        await state.habitsService.refresh(date: "2000-01-01")
        let presented = HabitsService(daemonConnection: connection)
        presented.snapshot.date = connection.currentDate
        let editor = HabitEditorModel(daemonConnection: connection, habitsService: state.habitsService,
            issueCreationService: state.issueCreationService, contextService: state.contextService,
            canPresent: { true }, actionService: { presented })
        let habit = HabitRowModel(id: 1, name: "Log", repoName: "Repo", streamName: "Stream",
            status: "", completed: false, durationMinutes: nil, targetMinutes: 10)
        editor.log(habit, durationMinutes: 10)
        await waitForIssueCreator { transport.methods.contains("habit.complete") }
        let request = try XCTUnwrap(transport.requests.last { $0.method == "habit.complete" })
        XCTAssertEqual(request.params["date"]?.stringValue, connection.currentDate)
        XCTAssertEqual(state.habitsService.snapshot.date, "2000-01-01")
    }

    func testUnexpectedlyHiddenWindowClearsPresentationState() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        let window = TestGlanceWindow()
        let glance = GlanceModel(appState: state, window: window)
        glance.toggle(appState: state)
        window.isVisible = false
        glance.reconcileWindowVisibility()
        XCTAssertFalse(glance.isPresented)
        glance.toggle(appState: state)
        XCTAssertTrue(glance.isPresented)
        glance.dismiss()
    }

}

@MainActor
private final class TestGlanceWindow: GlanceWindowPresenting {
    var dismissals = 0
    var isVisible = false
    func show(appState: CompanionAppState, model: GlanceModel) -> Bool { isVisible = true; return true }
    func dismiss(restoreFocus: Bool) { isVisible = false; dismissals += 1 }
}
