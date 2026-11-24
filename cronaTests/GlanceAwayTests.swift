import XCTest
@testable import crona

@MainActor
final class GlanceAwayTests: DaemonTestCase {
    func testManualAwayModeBlocksSetupAndCaptureUntilDisabled() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        let glance = state.glance

        await glance.setAwayMode(true)
        XCTAssertTrue(glance.isSelectedDayAway)
        glance.prepare()
        glance.toggleCapture()
        XCTAssertFalse(glance.showsSetup)
        XCTAssertFalse(glance.showsCapture)

        await glance.setAwayMode(false)
        XCTAssertFalse(glance.isSelectedDayAway)
        glance.prepare()
        XCTAssertTrue(glance.showsSetup)
    }

    func testRestRulesAndRecordedDaysCannotBeOverriddenFromGlance() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.restSpecificDatesFixture = [transport.logicalDate, "2001-02-01"]
        transport.awayDatesFixture = ["2001-02-02"]
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await state.coreSettingsService.refresh()
        let glance = state.glance

        XCTAssertTrue(glance.isSelectedDayAway)
        await glance.setAwayMode(false)
        await glance.setAwayMode(true)
        XCTAssertFalse(transport.methods.contains("settings.away_mode"))

        glance.day.select("2001-02-01")
        XCTAssertFalse(glance.isSelectedDayAway)
        glance.day.select("2001-02-02")
        XCTAssertTrue(glance.isSelectedDayAway)
        XCTAssertFalse(glance.canChangeAwayMode)
    }
}
