import XCTest
@testable import crona

@MainActor
final class GlancePreferencesTests: XCTestCase {
    func testDefaultsPreserveAllWidgets() {
        let preferences = GlancePreferences()
        XCTAssertEqual(preferences.normalizedOrder, GlanceWidget.allCases)
        XCTAssertTrue(GlanceWidget.allCases.allSatisfy(preferences.visible))
        XCTAssertFalse(preferences.rememberDate)
        XCTAssertFalse(preferences.unfinishedHabits)
    }

    func testOrderRemovesDuplicatesAndAppendsMissingWidgets() {
        var preferences = GlancePreferences()
        preferences.order = [.habits, .habits, .issues]
        XCTAssertEqual(preferences.normalizedOrder, [.habits, .issues, .calendar, .selection, .summary])
    }

    func testPreferencesRoundTrip() throws {
        var preferences = CompanionPreferences()
        preferences.glance.hidden = [.selection, .calendar]
        preferences.glance.rememberDate = true
        preferences.glance.lastDate = "2026-11-18"
        preferences.glance.unfinishedHabits = true
        let decoded = try JSONDecoder().decode(CompanionPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded.glance, preferences.glance)
        let legacy = try JSONDecoder().decode(CompanionPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.glance, GlancePreferences())
    }
}
