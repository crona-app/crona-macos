import Combine
import XCTest
@testable import crona

@MainActor
final class AlertTests: DaemonTestCase {
    func testCompanionAlertRoutingClassifiesTimerCompletionKinds() {
        XCTAssertTrue(CompanionAlertRouting.isTimerCompletion(kind: "timer.work_complete"))
        XCTAssertTrue(CompanionAlertRouting.isTimerCompletion(kind: "timer.break_complete"))
        XCTAssertFalse(CompanionAlertRouting.isTimerCompletion(kind: "timer.hard_limit_reached"))
    }

    func testCompanionAlertRoutingClaimsTimerAlertsForConnectedCompanion() {
        XCTAssertTrue(CompanionAlertRouting.isCompanionOwned(kind: "timer.work_complete"))
        XCTAssertTrue(CompanionAlertRouting.isCompanionOwned(kind: "timer.break_complete"))
        XCTAssertTrue(CompanionAlertRouting.isCompanionOwned(kind: "timer.break_deferral_warning"))
        XCTAssertFalse(CompanionAlertRouting.isCompanionOwned(kind: "timer.hard_limit_reached"))
        XCTAssertFalse(CompanionAlertRouting.isCompanionOwned(kind: "checkin.reminder"))
    }

    func testBreakDeferralPolicyRequiresRecentActivity() {
        var preferences = CompanionPreferences()
        preferences.breakScreenActivityExtensionSeconds = 60

        XCTAssertNil(BreakDeferralPolicy.seconds(preferences: preferences, recentlyActive: false))
        XCTAssertEqual(BreakDeferralPolicy.seconds(preferences: preferences, recentlyActive: true), 60)
    }

    func testBreakDeferralPolicyHonorsModeAndAcceptedDurations() {
        var preferences = CompanionPreferences()
        preferences.breakScreenActivityDeferral = .easyAndStrict
        preferences.breakScreenMode = .hard
        XCTAssertNil(BreakDeferralPolicy.seconds(preferences: preferences, recentlyActive: true))

        preferences.breakScreenActivityDeferral = .allModes
        preferences.breakScreenActivityExtensionSeconds = 45
        XCTAssertNil(BreakDeferralPolicy.seconds(preferences: preferences, recentlyActive: true))

        preferences.breakScreenActivityExtensionSeconds = 120
        XCTAssertEqual(BreakDeferralPolicy.seconds(preferences: preferences, recentlyActive: true), 120)
    }

    func testNotificationDeliveryReconciliationIsIdempotentWhenUnavailable() {
        let service = NotificationService()
        var publicationCount = 0
        let cancellable = service.objectWillChange.sink {
            publicationCount += 1
        }

        for _ in 0..<1_000 {
            service.reconcileDelivery()
        }

        XCTAssertEqual(service.deliveryState, .unavailable)
        XCTAssertEqual(publicationCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testNotificationDeliveryStatePublishesOnlyDistinctTransitions() {
        let service = NotificationService()
        var publicationCount = 0
        let cancellable = service.objectWillChange.sink {
            publicationCount += 1
        }

        XCTAssertFalse(service.setDeliveryState(.unavailable))
        XCTAssertTrue(service.setDeliveryState(.connecting))
        XCTAssertFalse(service.setDeliveryState(.connecting))
        XCTAssertTrue(service.setDeliveryState(.unavailable))
        XCTAssertFalse(service.setDeliveryState(.unavailable))

        XCTAssertEqual(publicationCount, 2)
        withExtendedLifetime(cancellable) {}
    }

    func testCompanionAlertRoutingMapsReminderCategories() {
        XCTAssertTrue(CompanionAlertRouting.isReminder(kind: "checkin.reminder"))
        XCTAssertTrue(CompanionAlertRouting.isReminder(kind: "daily_plan.reminder"))
        XCTAssertEqual(
            CompanionAlertRouting.reminderCategoryIdentifier(for: "checkin.reminder"),
            "crona.reminder.check-in"
        )
        XCTAssertEqual(
            CompanionAlertRouting.reminderCategoryIdentifier(for: "daily_plan.reminder"),
            "crona.reminder.daily-plan"
        )
    }

    func testCompanionAlertRoutingUsesTUIForWellbeingReminders() {
        XCTAssertTrue(CompanionAlertRouting.shouldOpenTUI(kind: "checkin.reminder"))
        XCTAssertTrue(CompanionAlertRouting.shouldOpenTUI(kind: "daily_plan.reminder"))
        XCTAssertFalse(CompanionAlertRouting.shouldOpenTUI(kind: "timer.work_complete"))
        XCTAssertFalse(CompanionAlertRouting.shouldOpenTUI(kind: "export.completed"))
    }

    func testCompanionAlertRoutingClassifiesExportCompletedKinds() {
        XCTAssertTrue(CompanionAlertRouting.isExportCompleted(kind: "export.completed"))
        XCTAssertFalse(CompanionAlertRouting.isExportCompleted(kind: "timer.work_complete"))
    }

    func testAlertDeliveryParsingSkipsMalformedPayloadsWithoutThrowing() throws {
        let malformed = try JSONDecoder().decode(
            CronaProtocolEvent.self,
            from: Data(#"{"type":"alert.delivery","payload":{"id":"alert-3"}}"#.utf8)
        )
        let unrelated = try JSONDecoder().decode(
            CronaProtocolEvent.self,
            from: Data(#"{"type":"alerts.status_changed","payload":{}}"#.utf8)
        )
        let valid = try JSONDecoder().decode(
            CronaProtocolEvent.self,
            from: Data(#"""
            {"type":"alert.delivery","payload":{"id":"alert-4",
              "alert":{"kind":"timer.work_complete","title":"Done","body":"","urgency":"low",
                "iconEnabled":true,"playSound":false},
              "deliverNotification":true,"playSound":false}}
            """#.utf8)
        )

        XCTAssertNil(NotificationService.alertDelivery(from: malformed))
        XCTAssertNil(NotificationService.alertDelivery(from: unrelated))
        XCTAssertEqual(NotificationService.alertDelivery(from: valid)?.alert.kind, "timer.work_complete")
    }

    func testAlertSettingsOptimisticProjectionMapsSoundAndProminence() throws {
        let settings = try JSONDecoder().decode(
            CronaAlertSettings.self,
            from: Data("""
            {
              "alertSoundPreset":"chime",
              "alertUrgency":"normal"
            }
            """.utf8)
        )

        let projected = settings
            .applying(key: "alertSoundPreset", value: .string("focus_gong"))
            .applying(key: "alertUrgency", value: .string("high"))

        XCTAssertEqual(projected.alertSoundPreset, .focusGong)
        XCTAssertEqual(projected.alertUrgency, .timeSensitive)
    }
}
