import XCTest
@testable import crona

@MainActor
final class StatsRefreshQueueTests: DaemonTestCase {
    func testEventBurstLoadsSelectedStatsOnlyOnce() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let stats = PopoverStatsService(daemonConnection: connection, backgroundRefreshEnabled: false)
        stats.selectDate(connection.currentDate)
        transport.libraryFixtures["dashboard.focus_score"] = [
            "startDate": connection.currentDate, "endDate": connection.currentDate,
            "score": 50, "level": "steady", "reason": "balanced", "workedSeconds": 0,
            "restSeconds": 0, "sessionCount": 0, "focusDays": 0, "days": 1, "targetWorkedSeconds": 0
        ]
        transport.libraryFixtures["metrics.range"] = [Any]()
        stats.setBackgroundRefreshEnabled(true)
        let scores = transport.methods.filter { $0 == "dashboard.focus_score" }.count
        let metrics = transport.methods.filter { $0 == "metrics.range" }.count
        for type in ["session.ended", "timer.state", "habit.completed", "issue.updated"] {
            NotificationCenter.default.post(name: .cronaDaemonEventReceived, object: CronaProtocolEvent(type: type, payload: nil))
        }
        await waitForIssueCreator { stats.snapshot.isConnected && !stats.snapshot.isLoading }
        XCTAssertEqual(transport.methods.filter { $0 == "dashboard.focus_score" }.count - scores, 1)
        XCTAssertEqual(transport.methods.filter { $0 == "metrics.range" }.count - metrics, 1)
    }

    func testEventsDuringRequestAreMergedIntoOneFollowUp() async {
        let queue = StatsRefreshQueue()
        let started = expectation(description: "First batch starts")
        let finished = expectation(description: "Follow-up batch finishes")
        var continuation: CheckedContinuation<Void, Never>?
        var batches: [Set<String>] = []
        queue.enqueue(dates: ["first"]) { dates, _ in
            batches.append(dates)
            if batches.count == 1 {
                await withCheckedContinuation { continuation = $0; started.fulfill() }
            } else { finished.fulfill() }
        }
        await fulfillment(of: [started], timeout: 3)
        queue.enqueue(dates: ["second"]) { _, _ in XCTFail("Unexpected replacement callback") }
        queue.enqueue(dates: ["third"]) { _, _ in XCTFail("Unexpected replacement callback") }
        continuation?.resume()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(batches, [["first"], ["second", "third"]])
        queue.cancel()
    }

    func testCancellationDropsPendingRequests() async {
        let queue = StatsRefreshQueue()
        let unexpected = expectation(description: "Cancelled work must not run")
        unexpected.isInverted = true
        queue.enqueue(dates: ["today"]) { _, _ in unexpected.fulfill() }
        queue.cancel()
        await fulfillment(of: [unexpected], timeout: 0.2)
    }
}
