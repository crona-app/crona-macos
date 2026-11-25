import XCTest
@testable import crona

@MainActor
final class GlancePreferencesTests: XCTestCase {
    func testDefaultsPreserveExistingWidgetsAndKeepWellbeingOptional() {
        let preferences = GlancePreferences()
        XCTAssertEqual(preferences.normalizedOrder, GlanceWidget.allCases)
        XCTAssertEqual(preferences.visibleWidgets, [.issues, .habits, .calendar, .selection, .summary])
        XCTAssertFalse(preferences.visible(.wellbeing))
        XCTAssertFalse(preferences.rememberDate)
        XCTAssertFalse(preferences.unfinishedHabits)
    }

    func testOrderRemovesDuplicatesAndAppendsMissingWidgets() {
        var preferences = GlancePreferences()
        preferences.order = [.habits, .habits, .issues]
        XCTAssertEqual(preferences.normalizedOrder, [.habits, .issues, .calendar, .selection, .summary, .wellbeing])
    }

    func testPreferencesRoundTrip() throws {
        var preferences = CompanionPreferences()
        preferences.glance.hidden = [.selection, .calendar]
        preferences.glance.layout = .singleColumn
        preferences.glance.rememberDate = true
        preferences.glance.lastDate = "2026-11-18"
        preferences.glance.unfinishedHabits = true
        let decoded = try JSONDecoder().decode(CompanionPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded.glance, preferences.glance)
        let legacy = try JSONDecoder().decode(CompanionPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.glance, GlancePreferences())
    }

    func testLegacyLayoutKeepsSavedOrderAndVisibility() throws {
        let legacy = try JSONDecoder().decode(
            GlancePreferences.self,
            from: Data(#"{"hidden":["calendar"],"order":["habits","issues","calendar","selection","summary"]}"#.utf8)
        )

        XCTAssertEqual(legacy.layout, .adaptive)
        XCTAssertEqual(legacy.visibleWidgets, [.habits, .issues, .selection, .summary])
    }

    func testPreviousColumnSettingsMigrateToAdaptiveGridAndKeepWellbeingEnabled() throws {
        let saved = try JSONDecoder().decode(
            GlancePreferences.self,
            from: Data(#"{"hidden":["selection"],"layout":"equalColumns","placements":{"wellbeing":"main"},"order":["wellbeing","issues"]}"#.utf8)
        )
        XCTAssertEqual(saved.layout, .adaptive)
        XCTAssertEqual(saved.visibleWidgets, [.wellbeing, .issues, .habits, .calendar, .summary])
    }

    func testReorderingChangesOrderWithinTheWorkspaceAndOverview() {
        var preferences = GlancePreferences()
        preferences.hidden.remove(.wellbeing)
        preferences.order = [.issues, .wellbeing, .habits, .calendar]
        preferences.move(.habits, by: -1)
        preferences.move(.calendar, by: -1)

        XCTAssertEqual(preferences.workWidgets, [.habits, .issues])
        XCTAssertEqual(preferences.overviewWidgets, [.calendar, .wellbeing, .summary])
        XCTAssertTrue(preferences.visible(.selection))
        XCTAssertFalse(preferences.overviewWidgets.contains(.selection))
    }

    func testResponsiveGroupsStackOnNarrowDisplays() {
        XCTAssertEqual(GlancePaneGridLayout.rowCounts(paneCount: 3, width: 1360, layout: .adaptive), [3])
        XCTAssertEqual(GlancePaneGridLayout.rowCounts(paneCount: 2, width: 1360, layout: .adaptive), [2])
        XCTAssertEqual(GlancePaneGridLayout.rowCounts(paneCount: 3, width: 700, layout: .adaptive), [1, 1, 1])
        XCTAssertEqual(GlancePaneGridLayout.rowCounts(paneCount: 3, width: 1360, layout: .singleColumn), [1, 1, 1])
    }

    func testContentHeightUsesOnlyPaneHeightsAndSpacing() {
        XCTAssertEqual(GlancePaneGridLayout.totalHeight([]), 0)
        XCTAssertEqual(GlancePaneGridLayout.totalHeight([108]), 108)
        XCTAssertEqual(GlancePaneGridLayout.totalHeight([132, 260]), 408)
    }
}
