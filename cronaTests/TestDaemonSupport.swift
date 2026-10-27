import Foundation
import XCTest
@testable import crona

/// Shared helpers for tests that drive app state against an in-memory daemon transport.
@MainActor
class DaemonTestCase: XCTestCase {
    final func waitForIssueCreator(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Issue creator operation did not complete")
    }

    final func issueCreatorConnection() async throws -> (DaemonConnectionService, IssueCreatorTestTransport) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"transport":"unix","endpoint":"/tmp/issue-creator-test.sock"}"#.utf8)
            .write(to: directory.appendingPathComponent("kernel.json"))
        let discovery = KernelDiscoveryService(configLoader: CronaConfigLoader(bundle: TestBundle.info([
            "CRONA_APP_ENV": "development", "CRONA_DAEMON_LABEL": "crona",
            "CRONA_RUNTIME_DIR": directory.path, "CRONA_KERNEL_EXECUTABLE": "crona-daemon",
            "CRONA_KERNEL_DEV_EXECUTABLE": "crona-daemon-dev"
        ]), environmentProvider: { [:] }))
        let transport = IssueCreatorTestTransport()
        let connection = DaemonConnectionService(kernelDiscovery: discovery,
            clientFactory: { _ in CronaDaemonClient(transport: transport) })
        connection.start()
        await waitForIssueCreator { connection.connectionState == .connected }
        await settleAsyncTasks()
        return (connection, transport)
    }

    /// Preferences backed by a throwaway suite so tests never write the dev app's real defaults.
    final func isolatedPreferences() -> PreferencesService {
        let suiteName = "cronaTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        return PreferencesService(defaults: UserDefaults(suiteName: suiteName)!)
    }

    final func postDaemonEvent(_ json: String) throws {
        let event = try JSONDecoder().decode(CronaProtocolEvent.self, from: Data(json.utf8))
        NotificationCenter.default.post(name: .cronaDaemonEventReceived, object: event)
    }

    final func settleAsyncTasks() async {
        for _ in 0..<6 {
            await Task.yield()
        }
    }
}

final class IssueCreatorTestTransport: CronaDaemonTransport {
    let logicalDate = "2001-02-03"
    private(set) var requests: [RequestWithParamsProbe] = []
    var methods: [String] { requests.map(\.method) }
    var suspendRefresh = false
    var failCreation = false
    var failEnd = false
    var hasAdhocSession = false
    var timerStateFixture: [String: Any]?
    var failExtend = false
    var provideDestinations = false
    var creationStatus = "planned"
    var createdFixture: [String: Any]?
    var failStatusChange = false
    var failStart = false
    var suspendStart = false
    var awayModeEnabled = false
    var healthDate: String?
    var todaySummaryIssuesFixture: [[String: Any]] = []
    var planEntriesFixture: [[String: Any]] = []
    var checkInByDate: [String: [String: Any]] = [:]
    var failCheckIn = false
    var failCarry = false
    var failCarryUndo = false
    var suspendCarry = false
    private var carryContinuation: CheckedContinuation<Void, Never>?
    var refreshContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    func resumeRefresh() {
        suspendRefresh = false
        refreshContinuation?.resume()
        refreshContinuation = nil
    }

    func resumeCarry() {
        suspendCarry = false
        carryContinuation?.resume()
        carryContinuation = nil
    }

    func resumeStart() {
        suspendStart = false
        startContinuation?.resume()
        startContinuation = nil
    }

    func send(_ request: Data) async throws -> Data {
        var object = try JSONSerialization.jsonObject(with: request) as! [String: Any]
        object["params"] = object["params"] ?? [:]
        let probe = try JSONDecoder().decode(RequestWithParamsProbe.self,
            from: JSONSerialization.data(withJSONObject: object))
        requests.append(probe)
        let result: Any
        switch probe.method {
        case "health.get":
            result = ["status": "ok", "db": true, "ok": 1, "uptime": 1,
                "currentDate": healthDate ?? logicalDate, "timezone": "Asia/Kolkata"] as [String: Any]
        case "kernel.info.get":
            result = ["pid": 1, "protocolVersion": CronaProtocolVersion.current.rawValue] as [String: Any]
        case "issue.create", "issue.update", "issue.set_todo", "issue.clear_todo":
            if probe.method == "issue.create", failCreation {
                throw NSError(domain: "IssueCreatorTests", code: 1)
            }
            let issue: [String: Any] = ["id": 42, "streamId": 7, "title": "New", "status": creationStatus,
                "workedSeconds": 0, "pinnedDaily": false,
                "todoForDate": probe.params["todoForDate"]?.stringValue as Any? ?? NSNull()]
            if probe.method == "issue.create" { createdFixture = issue }
            result = issue
        case "issue.today_summary":
            if suspendRefresh {
                await withCheckedContinuation { refreshContinuation = $0 }
            }
            result = ["date": logicalDate, "totalIssues": todaySummaryIssuesFixture.count,
                "issues": todaySummaryIssuesFixture,
                "totalEstimatedMinutes": 0, "completedIssues": 0,
                "abandonedIssues": 0, "workedSeconds": 0] as [String: Any]
        case "daily_plan.get":
            result = ["id": "plan", "date": probe.params["date"]?.stringValue ?? logicalDate, "createdAt": "", "updatedAt": "",
                "entries": planEntriesFixture] as [String: Any]
        case "timer.get_state":
            if let timerStateFixture {
                result = timerStateFixture
            } else if hasAdhocSession {
                result = ["state": "running", "sessionId": "adhoc-test", "adhoc": true, "elapsedSeconds": 901] as [String: Any]
            } else {
                result = ["state": "idle"]
            }
        case "timer.start":
            if suspendStart {
                await withCheckedContinuation { startContinuation = $0 }
            }
            if failStart { throw NSError(domain: "FocusStartTests", code: 1) }
            result = ["state": "idle"]
        case "settings.get_all" where awayModeEnabled:
            result = ["local": ["awayModeEnabled": true]]
        case "timer.extend":
            if failExtend { throw NSError(domain: "PopupTests", code: 1) }
            result = timerStateFixture ?? ["state": "idle"]
        case "timer.end":
            if failEnd { throw NSError(domain: "AdhocTests", code: 1) }
            hasAdhocSession = false
            timerStateFixture = nil
            result = ["state": "idle"]
        case "issue.list_all":
            result = (createdFixture.map { [$0] } ?? []) + todaySummaryIssuesFixture
        case "issue.change_status":
            if failStatusChange { throw NSError(domain: "AdhocTests", code: 2) }
            var issue = createdFixture ?? [:]
            issue["status"] = probe.params["status"]?.stringValue ?? "ready"
            createdFixture = issue
            result = issue
        case "habit.create", "habit.update":
            result = ["id": probe.params["id"]?.intValue ?? 9, "streamId": probe.params["streamId"]?.intValue ?? 7,
                "name": probe.params["name"]?.stringValue ?? "", "scheduleType": "daily", "weekdays": [Int](),
                "active": true, "repoId": 3, "repoName": "Repo", "streamName": "Stream"] as [String: Any]
        case "habit.delete", "issue.delete":
            result = ["ok": true]
        case "issue.carry", "issue.carry.undo":
            if probe.method == "issue.carry", suspendCarry {
                await withCheckedContinuation { carryContinuation = $0 }
            }
            if probe.method == "issue.carry" ? failCarry : failCarryUndo {
                throw NSError(domain: "CarryOverTests", code: 1)
            }
            result = ["id": probe.params["id"]?.intValue ?? 0, "streamId": 7, "title": "Carried",
                "status": "planned", "workedSeconds": 0, "pinnedDaily": false] as [String: Any]
        case "checkin.get":
            if failCheckIn { throw NSError(domain: "WellbeingTests", code: 1) }
            result = checkInByDate[probe.params["date"]?.stringValue ?? ""] ?? NSNull()
        case "habit.complete":
            result = ["id": 1, "habitId": probe.params["habitId"]?.intValue ?? 0,
                "date": probe.params["date"]?.stringValue ?? "", "status": "completed"] as [String: Any]
        case "habit.list_due":
            result = [Any]()
        case "repo.list":
            result = provideDestinations ? [["id": 3, "name": "Repo"]] : []
        case "stream.list":
            result = provideDestinations ? [["id": 7, "repoId": 3, "name": "Stream"]] : []
        default:
            result = NSNull()
        }
        return try JSONSerialization.data(withJSONObject: ["id": object["id"]!, "result": result])
    }

    func openEventStream(with request: Data) async throws -> AsyncThrowingStream<CronaProtocolEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

final class TestBundle: Bundle, @unchecked Sendable {
    private let values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
        super.init()
    }

    static func info(_ values: [String: Any]) -> Bundle {
        TestBundle(values: values)
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        values[key]
    }
}

struct RequestWithParamsProbe: Decodable {
    let id: String
    let method: String
    let params: [String: JSONScalar]
}

enum JSONScalar: Decodable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([JSONScalar])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let array = try? container.decode([JSONScalar].self) {
            self = .array(array)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .int(value) = self { return value }
        return nil
    }

    var intArrayValue: [Int]? {
        if case let .array(values) = self { return values.compactMap(\.intValue) }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }
}
