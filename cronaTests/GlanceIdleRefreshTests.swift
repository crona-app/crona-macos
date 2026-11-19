import Combine
import XCTest
@testable import crona

@MainActor
final class GlanceIdleRefreshTests: DaemonTestCase {
    func testInactiveServicesSkipInitialAndEventRefreshButAllowExplicitLoading() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let daily = DailyFocusService(daemonConnection: connection, backgroundRefreshEnabled: false)
        let habits = HabitsService(daemonConnection: connection, backgroundRefreshEnabled: false)
        let stats = PopoverStatsService(daemonConnection: connection, backgroundRefreshEnabled: false)
        let methods: Set<String> = ["issue.today_summary", "habit.list_due", "dashboard.focus_score", "metrics.range"]
        func count() -> Int { transport.methods.filter(methods.contains).count }
        let initial = count()
        try postDaemonEvent(#"{"type":"session.ended","payload":{"sessionId":"test"}}"#)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(count(), initial)
        await daily.refresh()
        await habits.refresh()
        await stats.refresh()
        XCTAssertTrue(daily.snapshot.isConnected)
        XCTAssertTrue(habits.snapshot.isConnected)
        daily.setBackgroundRefreshEnabled(false)
        habits.setBackgroundRefreshEnabled(false)
        stats.setBackgroundRefreshEnabled(false)
        XCTAssertTrue(daily.snapshot.issues.isEmpty)
        XCTAssertTrue(habits.snapshot.items.isEmpty)
        XCTAssertNil(stats.snapshot.focusScore)
        XCTAssertNil(stats.cachedSnapshot(for: connection.currentDate))
        let suspended = count()
        try postDaemonEvent(#"{"type":"issue.updated","payload":{}}"#)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(count(), suspended)
        let resumed = expectation(description: "Automatic refresh resumes")
        let observation = daily.$snapshot.filter(\.isConnected).prefix(1).sink { _ in resumed.fulfill() }
        daily.setBackgroundRefreshEnabled(true)
        try postDaemonEvent(#"{"type":"issue.updated","payload":{}}"#)
        await fulfillment(of: [resumed], timeout: 3)
        withExtendedLifetime(observation) {}
    }
}
