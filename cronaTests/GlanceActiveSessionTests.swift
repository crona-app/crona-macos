import XCTest
@testable import crona

@MainActor
final class GlanceActiveSessionTests: DaemonTestCase {
    func testActiveSessionBlocksSetupAndCaptureWithoutChangingDraft() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = ["state": "running", "sessionId": "focus-test", "adhoc": true, "elapsedSeconds": 20]
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await state.timerService.refresh()
        XCTAssertTrue(state.hasActiveFocusSession)
        state.glance.capture.text = "Keep this draft"
        state.glance.prepare()
        state.glance.toggleCapture()
        XCTAssertFalse(state.glance.showsSetup)
        XCTAssertFalse(state.glance.showsCapture)
        XCTAssertEqual(state.glance.capture.text, "Keep this draft")
    }
}
