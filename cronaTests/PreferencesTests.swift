import AppKit
import SwiftUI
import XCTest
@testable import crona

@MainActor
final class PreferencesTests: DaemonTestCase {
    func testPreferencesDefaultFloatingTimerHUDOffAndPersistsOptIn() throws {
        let legacy = try JSONDecoder().decode(CompanionPreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.showTimerHUD)
        XCTAssertFalse(legacy.showTimerHUDProgress)
        XCTAssertEqual(legacy.timerHUDPosition, .bottomCenter)
        XCTAssertEqual(legacy.timerHUDSize, .spacious)

        var enabled = legacy
        enabled.showTimerHUD = true
        enabled.showTimerHUDProgress = true
        let decoded = try JSONDecoder().decode(
            CompanionPreferences.self,
            from: JSONEncoder().encode(enabled)
        )
        XCTAssertTrue(decoded.showTimerHUD)
        XCTAssertTrue(decoded.showTimerHUDProgress)
    }

    func testFloatingTimerPreferencesPersistPositionAndSize() throws {
        var preferences = CompanionPreferences()
        preferences.timerHUDPosition = .topRight
        preferences.timerHUDSize = .compact

        let decoded = try JSONDecoder().decode(
            CompanionPreferences.self,
            from: JSONEncoder().encode(preferences)
        )

        XCTAssertEqual(decoded.timerHUDPosition, .topRight)
        XCTAssertEqual(decoded.timerHUDSize, .compact)
    }

    func testFloatingTimerSizeProfilesHaveDescendingPanelSizes() {
        XCTAssertGreaterThan(TimerHUDSize.spacious.panelSize.width, TimerHUDSize.regular.panelSize.width)
        XCTAssertGreaterThan(TimerHUDSize.regular.panelSize.width, TimerHUDSize.compact.panelSize.width)
        XCTAssertGreaterThan(TimerHUDSize.spacious.panelSize.height, TimerHUDSize.regular.panelSize.height)
        XCTAssertGreaterThan(TimerHUDSize.regular.panelSize.height, TimerHUDSize.compact.panelSize.height)
        XCTAssertEqual(TimerHUDSize.compact.panelSize, CGSize(width: 220, height: 64))
    }

    func testSettingsDestinationsUseConsolidatedInformationArchitecture() {
        XCTAssertTrue(SettingsDestination.allCases.contains(.daySchedule))
        XCTAssertTrue(SettingsDestination.allCases.contains(.advanced))
        XCTAssertFalse(SettingsDestination.allCases.map(\.rawValue).contains("runtime"))
        XCTAssertFalse(SettingsDestination.allCases.map(\.rawValue).contains("diagnostics"))
        XCTAssertFalse(SettingsDestination.allCases.map(\.rawValue).contains("updates"))
    }

    func testPreferencesPersist() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = PreferencesService(defaults: defaults)
        service.preferences.appearance = .dark
        service.preferences.menuBarDisplayMode = .textOnly
        service.preferences.menuBarIdleTextMode = .focusToday
        service.preferences.menuBarTimeFormat = .adaptive
        service.preferences.hideDockIconWhenNoWindowsOpen = false
        service.preferences.smartPauseEnabled = true
        service.preferences.smartPauseOnLock = false
        service.preferences.smartPauseOnDisplaySleep = false
        service.preferences.smartPauseOnInactivity = true
        service.preferences.smartPauseIdleSeconds = 30
        service.preferences.showHardLimitActionPopups = false
        service.preferences.showInactivityActionPopups = false
        service.preferences.inactivityPopupPosition = .bottomRight
        service.preferences.breakScreenEnabled = true
        service.preferences.breakScreenMode = .strict
        service.preferences.breakScreenStrictDelaySeconds = 30
        service.preferences.breakScreenBackgroundStyle = .gradient
        service.preferences.breakScreenGradientPreset = .ocean
        service.preferences.appUpdateChannel = .beta
        service.preferences.tuiCommand = "crona tui"

        let reloaded = PreferencesService(defaults: defaults)
        XCTAssertEqual(reloaded.preferences.appearance, .dark)
        XCTAssertEqual(reloaded.preferences.menuBarDisplayMode, .textOnly)
        XCTAssertEqual(reloaded.preferences.menuBarIdleTextMode, .focusToday)
        XCTAssertEqual(reloaded.preferences.menuBarTimeFormat, .adaptive)
        XCTAssertFalse(reloaded.preferences.hideDockIconWhenNoWindowsOpen)
        XCTAssertTrue(reloaded.preferences.smartPauseEnabled)
        XCTAssertFalse(reloaded.preferences.smartPauseOnLock)
        XCTAssertFalse(reloaded.preferences.smartPauseOnDisplaySleep)
        XCTAssertTrue(reloaded.preferences.smartPauseOnInactivity)
        XCTAssertEqual(reloaded.preferences.smartPauseIdleSeconds, 30)
        XCTAssertFalse(reloaded.preferences.showHardLimitActionPopups)
        XCTAssertFalse(reloaded.preferences.showInactivityActionPopups)
        XCTAssertEqual(reloaded.preferences.inactivityPopupPosition, .bottomRight)
        XCTAssertTrue(reloaded.preferences.breakScreenEnabled)
        XCTAssertEqual(reloaded.preferences.breakScreenMode, .strict)
        XCTAssertEqual(reloaded.preferences.breakScreenStrictDelaySeconds, 30)
        XCTAssertEqual(reloaded.preferences.breakScreenBackgroundStyle, .gradient)
        XCTAssertEqual(reloaded.preferences.breakScreenGradientPreset, .ocean)
        XCTAssertEqual(reloaded.preferences.appUpdateChannel, .beta)
        XCTAssertEqual(reloaded.preferences.tuiCommand, "crona tui")
    }

    func testCompanionAppearanceResolvesExplicitAndSystemModes() {
        XCTAssertEqual(
            CompanionAppearance.system.resolvedColorScheme(using: .light),
            .light
        )
        XCTAssertEqual(
            CompanionAppearance.system.resolvedColorScheme(using: .dark),
            .dark
        )
        XCTAssertEqual(
            CompanionAppearance.light.resolvedColorScheme(using: .dark),
            .light
        )
        XCTAssertEqual(
            CompanionAppearance.dark.resolvedColorScheme(using: .light),
            .dark
        )
    }

    func testPreferencesDecodeValuesSavedBeforeIdleTextSettingExisted() throws {
        let data = """
        {
          "launchAtLogin": true,
          "menuBarDisplayMode": "iconAndText",
          "menuBarTimeFormat": "clock",
          "menuBarShowsSeconds": false,
          "pinPopover": true,
          "tuiCommand": "crona"
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(CompanionPreferences.self, from: data)

        XCTAssertEqual(preferences.menuBarDisplayMode, .iconAndText)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.menuBarIdleTextMode, .idle)
        XCTAssertTrue(preferences.hideDockIconWhenNoWindowsOpen)
        XCTAssertFalse(preferences.smartPauseEnabled)
        XCTAssertTrue(preferences.smartPauseOnLock)
        XCTAssertTrue(preferences.smartPauseOnDisplaySleep)
        XCTAssertTrue(preferences.smartPauseOnInactivity)
        XCTAssertEqual(preferences.smartPauseIdleSeconds, 120)
        XCTAssertTrue(preferences.showHardLimitActionPopups)
        XCTAssertTrue(preferences.showHardLimitWarningIndicator)
        XCTAssertEqual(preferences.hardLimitWarningLeadSeconds, 10)
        XCTAssertTrue(preferences.showInactivityActionPopups)
        XCTAssertEqual(preferences.inactivityPopupPosition, .topCenter)
        XCTAssertFalse(preferences.breakScreenEnabled)
        XCTAssertEqual(preferences.breakScreenMode, .easy)
        XCTAssertEqual(preferences.breakScreenStrictDelaySeconds, 15)
        XCTAssertEqual(preferences.breakScreenBackgroundStyle, .systemWallpaper)
        XCTAssertNil(preferences.appUpdateChannel)
    }

    func testPreferencesMigrateLegacyInactivityPopupPositions() throws {
        let expectedPositions: [(String, CompanionPopupPosition)] = [
            ("top", .topCenter),
            ("bottom", .bottomCenter),
            ("center", .topCenter),
            ("left", .topLeft),
            ("right", .topRight)
        ]

        for (legacyValue, expectedPosition) in expectedPositions {
            let data = "{\"inactivityPopupPosition\":\"\(legacyValue)\"}".data(using: .utf8)!
            let preferences = try JSONDecoder().decode(CompanionPreferences.self, from: data)
            XCTAssertEqual(preferences.inactivityPopupPosition, expectedPosition, legacyValue)
        }
    }

    func testPreferencesDefaultHardLimitPopupEnabled() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = PreferencesService(defaults: defaults)

        XCTAssertTrue(service.preferences.showHardLimitActionPopups)
    }

    func testPreferencesDefaultDockIconHidesWhenNoWindowsAreOpen() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = PreferencesService(defaults: defaults)

        XCTAssertTrue(service.preferences.hideDockIconWhenNoWindowsOpen)
    }

    func testHardLimitWarningLeadTimeUsesFixedPresets() {
        XCTAssertEqual(CompanionPreferences.hardLimitWarningLeadTimeOptions, [10, 20, 30])
        XCTAssertEqual(CompanionPreferences.normalizedHardLimitWarningLeadSeconds(1), 10)
        XCTAssertEqual(CompanionPreferences.normalizedHardLimitWarningLeadSeconds(17), 20)
        XCTAssertEqual(CompanionPreferences.normalizedHardLimitWarningLeadSeconds(60), 30)
    }

    func testBreakScreenStrictDelayUsesFixedPresets() {
        XCTAssertEqual(
            CompanionPreferences.breakScreenStrictDelayOptions,
            [5, 10, 15, 30, 60]
        )
        XCTAssertEqual(CompanionPreferences.normalizedBreakScreenStrictDelaySeconds(1), 5)
        XCTAssertEqual(CompanionPreferences.normalizedBreakScreenStrictDelaySeconds(18), 15)
        XCTAssertEqual(CompanionPreferences.normalizedBreakScreenStrictDelaySeconds(100), 60)
    }

    func testSmartPauseIdleDurationUsesShortPresets() {
        XCTAssertEqual(
            CompanionPreferences.smartPauseIdleOptions,
            [30, 60, 120, 300, 600]
        )
        XCTAssertEqual(CompanionPreferences.normalizedSmartPauseIdleSeconds(20), 30)
        XCTAssertEqual(CompanionPreferences.normalizedSmartPauseIdleSeconds(100), 120)
        XCTAssertEqual(CompanionPreferences.normalizedSmartPauseIdleSeconds(480), 600)
    }

    func testMenuBarTimeFormatMigratesExpandedToAdaptive() throws {
        let data = Data("\"expanded\"".utf8)
        let format = try JSONDecoder().decode(MenuBarTimeFormat.self, from: data)
        XCTAssertEqual(format, .adaptive)
    }
}
