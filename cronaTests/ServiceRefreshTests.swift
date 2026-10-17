import XCTest
@testable import crona

@MainActor
final class ServiceRefreshTests: DaemonTestCase {
    func testDailyFocusBuildsPlannedOrderFromPlanEntries() {
        let summary = CronaDailyIssueSummary(
            date: "2026-07-13",
            totalIssues: 2,
            issues: [
                CronaIssue(id: 2, streamID: 20, title: "Second", status: "planned", estimateMinutes: 30, workedSeconds: 0, pinnedDaily: false, todoForDate: "2026-07-13", completedAt: nil, abandonedAt: nil),
                CronaIssue(id: 1, streamID: 10, title: "First", status: "planned", estimateMinutes: 45, workedSeconds: 0, pinnedDaily: false, todoForDate: "2026-07-13", completedAt: nil, abandonedAt: nil)
            ],
            totalEstimatedMinutes: 75,
            completedIssues: 0,
            abandonedIssues: 0,
            workedSeconds: 0
        )
        let plan = CronaDailyPlan(
            id: "plan-1",
            date: "2026-07-13",
            createdAt: "2026-07-13T00:00:00Z",
            updatedAt: "2026-07-13T00:00:00Z",
            entries: [
                CronaDailyPlanEntry(id: "entry-1", date: "2026-07-13", issueID: 1, source: "todo_for_date", status: "planned", committedAt: "2026-07-13T00:00:00Z", baselineDate: "2026-07-13", currentPlannedDate: "2026-07-13", postponeCount: 0, currentDelayedDays: 0, maxDelayedDays: 0, failScore: 0),
                CronaDailyPlanEntry(id: "entry-2", date: "2026-07-13", issueID: 2, source: "todo_for_date", status: "planned", committedAt: "2026-07-13T00:00:00Z", baselineDate: "2026-07-13", currentPlannedDate: "2026-07-13", postponeCount: 0, currentDelayedDays: 0, maxDelayedDays: 0, failScore: 0)
            ]
        )

        let issues = DailyFocusService.buildIssues(summary: summary, plan: plan)

        XCTAssertEqual(issues.map(\.id), [1, 2])
    }

    func testDiagnosticsTextContainsCoreFields() {
        let snapshot = DiagnosticsSnapshot(
            connectionState: "Connected",
            protocolVersion: "1.1",
            kernelVersion: "stable",
            runtimeDirectory: "/tmp/crona",
            healthSummary: "ok | db=true | uptime=10s",
            lastReconnect: "Today",
            endpoint: "/tmp/crona/kernel.sock",
            transport: "unix_socket",
            alertBackend: "usernotifications",
            lastError: nil
        )

        XCTAssertTrue(snapshot.text.contains("Connection State: Connected"))
        XCTAssertTrue(snapshot.text.contains("Runtime Directory: /tmp/crona"))
    }

    func testTimerServiceRefreshesForEndExtendAndBreakDeferralEvents() {
        XCTAssertTrue(TimerService.shouldRefresh(for: "session.ended"))
        XCTAssertTrue(TimerService.shouldRefresh(for: "timer.extended"))
        XCTAssertTrue(TimerService.shouldRefresh(for: "timer.break_deferral_warning"))
        XCTAssertTrue(TimerService.shouldRefresh(for: "timer.break_deferred"))
        XCTAssertFalse(TimerService.shouldRefresh(for: "habit.completed"))
    }

    func testContextServiceRefreshesForEndExtendAndBreakDeferralEvents() {
        XCTAssertTrue(ContextService.shouldRefresh(for: "session.ended"))
        XCTAssertTrue(ContextService.shouldRefresh(for: "timer.extended"))
        XCTAssertTrue(ContextService.shouldRefresh(for: "timer.break_deferral_warning"))
        XCTAssertTrue(ContextService.shouldRefresh(for: "timer.break_deferred"))
        XCTAssertFalse(ContextService.shouldRefresh(for: "habit.completed"))
    }

    func testHistoryChangedEventRefreshesDailyAndStats() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let daily = DailyFocusService(daemonConnection: connection)
        let stats = PopoverStatsService(daemonConnection: connection)
        await settleAsyncTasks()
        let before = transport.methods.filter { $0 == "issue.today_summary" }.count
        let revision = stats.calendarCacheRevision
        NotificationCenter.default.post(name: .cronaDaemonEventReceived,
            object: CronaProtocolEvent(type: "session.history_changed", payload: nil))
        await waitForIssueCreator {
            transport.methods.filter { $0 == "issue.today_summary" }.count > before
                && stats.calendarCacheRevision > revision
                && daily.snapshot.date == transport.logicalDate
        }
        XCTAssertEqual(daily.snapshot.date, transport.logicalDate)
    }
}
