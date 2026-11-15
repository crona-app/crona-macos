import XCTest

@testable import crona

@MainActor
final class HistoricalAwayDayTests: DaemonTestCase {
    func testRecordedAwayFollowsSelectedDateAndReturnsToNormalImmediately() {
        let day = PopoverDayModel(today: { "2026-11-15" })
        let settings = CronaCoreSettings(awayDates: ["2026-11-12"])
        XCTAssertFalse(day.isRecordedAway(in: settings))
        day.select("2026-11-12")
        XCTAssertTrue(day.isRecordedAway(in: settings))
        day.showNextDay()
        XCTAssertFalse(day.isRecordedAway(in: settings))
        day.showToday()
        XCTAssertFalse(day.isRecordedAway(in: settings))
    }

    func testCurrentAwayModeAndRestRulesDoNotInventHistoricalAwayDates() {
        let day = PopoverDayModel(today: { "2026-11-15" })
        day.select("2026-11-12")
        let settings = CronaCoreSettings(awayModeEnabled: true, restWeekdays: [4], restSpecificDates: ["2026-11-12"])
        XCTAssertTrue(settings.isConfiguredRestDate(day.selectedDate))
        XCTAssertFalse(day.isRecordedAway(in: settings))
    }

    func testRecordedAwayTreatmentUsesSettingsWithoutWaitingForDailyData() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        let awayDate = "2001-02-01"
        transport.awayDatesFixture = [awayDate]
        await appState.coreSettingsService.refresh()
        appState.day.select(awayDate)
        XCTAssertTrue(appState.day.isRecordedAway(in: appState.coreSettingsService.settings))
        XCTAssertFalse(appState.todayIsAway)
        XCTAssertFalse(transport.methods.contains("settings.patch"))
        transport.awayDatesFixture = []
        await appState.coreSettingsService.refresh()
        XCTAssertFalse(appState.day.isRecordedAway(in: appState.coreSettingsService.settings))
    }
}
