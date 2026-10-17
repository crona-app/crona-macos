import XCTest
@testable import crona

@MainActor
final class PopoverNavigationTests: DaemonTestCase {
    func testPopoverTabSelectionWorksWhileIdle() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)

        appState.setSelectedPopoverTab(.stats)

        XCTAssertEqual(appState.selectedPopoverTab, .stats)
    }

    func testPopoverTabStaysOnNowDuringActiveSession() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = ["state": "running", "sessionId": "s1", "elapsedSeconds": 60]
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()

        appState.setSelectedPopoverTab(.stats)

        XCTAssertEqual(appState.selectedPopoverTab, .now)
    }

    func testSelectingWellbeingTabRefreshesWellbeing() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        await settleAsyncTasks()
        let checkInsBefore = transport.methods.filter { $0 == "checkin.get" }.count

        appState.setSelectedPopoverTab(.wellbeing)

        await waitForIssueCreator { transport.methods.filter { $0 == "checkin.get" }.count > checkInsBefore }
    }

    func testPopoverResetClearsRouteTabAndEndsStatsCalendar() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.openIssueDetails(DailyFocusIssue(id: 42, streamID: 7, title: "Fixture", status: "planned",
            estimateMinutes: nil, workedSeconds: 0, todoForDate: nil))
        appState.setSelectedPopoverTab(.stats)
        appState.isStatsCalendarPresented = true
        appState.popoverStatsService.beginCalendar()
        XCTAssertNotNil(appState.popoverStatsService.calendarMonthDate)

        appState.resetPopoverPresentation()

        XCTAssertNil(appState.popoverDetailsRoute)
        XCTAssertEqual(appState.selectedPopoverTab, .now)
        XCTAssertFalse(appState.isStatsCalendarPresented)
        XCTAssertNil(appState.popoverStatsService.calendarMonthDate)
    }

    func testPopoverDetailsRouteOpensAndDismisses() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)

        appState.openIssueDetails(DailyFocusIssue(id: 42, streamID: 7, title: "Fixture", status: "planned",
            estimateMinutes: nil, workedSeconds: 0, todoForDate: nil))
        XCTAssertEqual(appState.popoverDetailsRoute, .issueDetails(issueID: 42))

        appState.dismissDetails()
        XCTAssertNil(appState.popoverDetailsRoute)
    }

    func testPopoverOpenReconcilesStaleDatesToDaemonDate() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        await settleAsyncTasks()
        transport.healthDate = "2001-02-04"

        await appState.reconcileFunctionalDateOnPopoverOpen()

        XCTAssertEqual(appState.dailyFocusService.snapshot.date, "2001-02-04")
        XCTAssertEqual(appState.habitsService.snapshot.date, "2001-02-04")
        XCTAssertEqual(appState.wellbeingService.snapshot.date, "2001-02-04")
        XCTAssertEqual(appState.popoverStatsService.functionalDate, "2001-02-04")
    }

    func testPopoverOpenSkipsReconcileWhenDatesMatch() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        await settleAsyncTasks()
        await appState.reconcileFunctionalDateOnPopoverOpen()
        let requestsBefore = transport.methods.count

        await appState.reconcileFunctionalDateOnPopoverOpen()

        XCTAssertEqual(Array(transport.methods.dropFirst(requestsBefore)), ["health.get"])
    }
}
