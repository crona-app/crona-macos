import XCTest
@testable import crona

@MainActor
final class DaemonClientTests: DaemonTestCase {
    func testDaemonClientFetchesKernelInfo() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "pid":42,
            "transport":"unix_socket",
            "endpoint":"/tmp/kernel.sock",
            "socketPath":"/tmp/kernel.sock",
            "protocolVersion":"1.1",
            "startedAt":"2026-06-09T00:00:00Z",
            "scratchDir":"/tmp",
            "env":"development",
            "executablePath":"/Applications/Crona.app/Contents/MacOS/crona-daemon",
            "runningChannel":"stable",
            "runningIsBeta":false
          }
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let fetchedInfo = try await client.kernelInfoGet()

        XCTAssertEqual(fetchedInfo.protocolVersion, "1.1")
        XCTAssertEqual(fetchedInfo.endpoint, "/tmp/kernel.sock")

        let request: Data = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "kernel.info.get")
    }

    func testDaemonClientTreatsMissingWellbeingCheckInAsEmptyResult() async throws {
        let response = Data(#"{"id":"response-1","result":null}"#.utf8)
        let client = CronaDaemonClient(transport: CapturingDaemonTransport(responseData: response))

        let checkIn = try await client.checkInGet(date: "2026-08-14")

        XCTAssertNil(checkIn)
    }

    func testDaemonClientDecodesExistingWellbeingCheckIn() async throws {
        let response = Data(#"{"id":"response-1","result":{"date":"2026-08-14","mood":4,"energy":3,"sleepHours":7.5,"sleepScore":82,"screenTimeMinutes":95,"notes":"Steady day","createdAt":"now","updatedAt":"now"}}"#.utf8)
        let client = CronaDaemonClient(transport: CapturingDaemonTransport(responseData: response))

        let checkIn = try await client.checkInGet(date: "2026-08-14")

        XCTAssertEqual(checkIn?.mood, 4)
        XCTAssertEqual(checkIn?.energy, 3)
    }

    func testDaemonClientRejectsWellbeingResponseWithoutResult() async {
        let response = Data(#"{"id":"response-1"}"#.utf8)
        let client = CronaDaemonClient(transport: CapturingDaemonTransport(responseData: response))

        do {
            _ = try await client.checkInGet(date: "2026-08-14")
            XCTFail("Expected malformed response")
        } catch let error as CronaConnectionFailure {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDaemonClientBuildsKernelShutdownRequest() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{"ok":true}
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let result = try await client.kernelShutdown()

        XCTAssertTrue(result.ok)
        let request: Data = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "kernel.shutdown")
    }

    func testDaemonClientBuildsTimerAdvanceRequest() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "state":"running",
            "sessionId":"session-1",
            "segmentType":"short_break",
            "hardLimitActive":true,
            "hardLimitKind":"pomodoro"
          }
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let result = try await client.timerAdvance()

        XCTAssertEqual(result.segmentType, "short_break")
        let request: Data = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "timer.advance")
    }

    func testDaemonClientBuildsAwayModeRequest() async throws {
        let transport = CapturingDaemonTransport(
            responseData: #"{"id":"response-1","result":{"ok":true}}"#.data(using: .utf8)!
        )
        let client = CronaDaemonClient(transport: transport)

        _ = try await client.setAwayMode(enabled: true)

        let request = try XCTUnwrap(transport.requestData)
        let probe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(probe.method, "settings.away_mode")
        XCTAssertEqual(probe.params["enabled"]?.boolValue, true)
    }

    func testDaemonClientBuildsAlertDeliveryAckRequest() async throws {
        let response = """
        {"id":"response-1","result":{"ok":true}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        _ = try await client.acknowledgeAlertDelivery(
            CronaAlertDeliveryAck(
                deliveryID: "alert-1",
                notificationAccepted: true,
                soundAccepted: false,
                actionID: "timer.defer_break",
                actionSeconds: 60
            )
        )

        let request = try XCTUnwrap(transport.requestData)
        let probe = try JSONDecoder().decode(AlertDeliveryAckRequestProbe.self, from: request)
        XCTAssertEqual(probe.method, "alerts.delivery.ack")
        XCTAssertEqual(probe.params.deliveryID, "alert-1")
        XCTAssertTrue(probe.params.notificationAccepted)
        XCTAssertFalse(probe.params.soundAccepted)
        XCTAssertEqual(probe.params.actionID, "timer.defer_break")
        XCTAssertEqual(probe.params.actionSeconds, 60)
    }

    func testDaemonClientBuildsAlertDeliverySubscription() async throws {
        let transport = CapturingDaemonTransport(responseData: Data())
        let client = CronaDaemonClient(transport: transport)

        let stream = try await client.subscribeToAlertDeliveries(
            capabilities: CronaAlertDeliveryCapability(
                clientID: "mac-client",
                notifications: true,
                sounds: true
            )
        )
        for try await _ in stream {}

        let request = try XCTUnwrap(transport.requestData)
        let probe = try JSONDecoder().decode(AlertDeliverySubscriptionProbe.self, from: request)
        XCTAssertEqual(probe.method, "alerts.delivery.subscribe")
        XCTAssertEqual(probe.params.clientID, "mac-client")
        XCTAssertTrue(probe.params.notifications)
        XCTAssertTrue(probe.params.sounds)
    }

    func testDaemonClientBuildsListDueHabitsRequest() async throws {
        let response = """
        {"id":"response-1","result":[]}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let habits = try await client.listDueHabits(date: "2026-07-13")

        XCTAssertEqual(habits.count, 0)
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "habit.list_due")
        XCTAssertEqual(requestProbe.params["date"]?.stringValue, "2026-07-13")
    }

    func testDaemonClientBuildsIssueStatusTransitionsRequest() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "id":42,
            "currentStatus":"in_progress",
            "allowedStatuses":["planned","blocked","in_review","done","abandoned"]
          }
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let result = try await client.issueStatusTransitions(issueID: 42)

        XCTAssertEqual(result.currentStatus, "in_progress")
        XCTAssertEqual(result.allowedStatuses, [.planned, .blocked, .inReview, .done, .abandoned])
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "issue.status_transitions")
        XCTAssertEqual(requestProbe.params["id"]?.intValue, 42)
    }

    func testDaemonClientBuildsRepoAndStreamListRequests() async throws {
        let repoTransport = CapturingDaemonTransport(responseData: Data(#"{"id":"response-1","result":[{"id":3,"name":"Crona"}]}"#.utf8))
        let repos = try await CronaDaemonClient(transport: repoTransport).listRepos()
        XCTAssertEqual(repos, [CronaRepo(id: 3, name: "Crona")])
        let repoRequest = try JSONDecoder().decode(RequestProbe.self, from: XCTUnwrap(repoTransport.requestData))
        XCTAssertEqual(repoRequest.method, "repo.list")

        let streamTransport = CapturingDaemonTransport(responseData: Data(#"{"id":"response-1","result":[{"id":7,"repoId":3,"name":"macOS"}]}"#.utf8))
        let streams = try await CronaDaemonClient(transport: streamTransport).listStreams(repoID: 3)
        XCTAssertEqual(streams, [CronaStream(id: 7, repoID: 3, name: "macOS")])
        let request = try JSONDecoder().decode(RequestWithParamsProbe.self, from: XCTUnwrap(streamTransport.requestData))
        XCTAssertEqual(request.method, "stream.list")
        XCTAssertEqual(request.params["repoId"]?.intValue, 3)
    }

    func testDaemonClientBuildsIssueCreateRequestAndOmitsEmptyOptions() async throws {
        let transport = CapturingDaemonTransport(responseData: issueResponseData(status: "planned", todoForDate: "2026-08-13"))
        let client = CronaDaemonClient(transport: transport)
        _ = try await client.createIssue(CronaCreateIssueRequest(
            streamID: 7,
            title: "Ship quick create",
            description: nil,
            estimateMinutes: 45,
            todoForDate: "2026-08-13"
        ))

        let request = try JSONDecoder().decode(RequestWithParamsProbe.self, from: XCTUnwrap(transport.requestData))
        XCTAssertEqual(request.method, "issue.create")
        XCTAssertEqual(request.params["streamId"]?.intValue, 7)
        XCTAssertEqual(request.params["title"]?.stringValue, "Ship quick create")
        XCTAssertEqual(request.params["estimateMinutes"]?.intValue, 45)
        XCTAssertEqual(request.params["todoForDate"]?.stringValue, "2026-08-13")
        XCTAssertNil(request.params["description"])
        XCTAssertNil(request.params["notes"])
    }

    func testDaemonClientBuildsIssueUpdateRequest() async throws {
        let transport = CapturingDaemonTransport(responseData: issueResponseData(status: "planned", todoForDate: nil))
        let client = CronaDaemonClient(transport: transport)
        _ = try await client.updateIssue(
            CronaUpdateIssueRequest(
                id: 42,
                title: "Updated issue",
                description: "More detail",
                estimateMinutes: 90
            )
        )

        let request = try JSONDecoder().decode(RequestWithParamsProbe.self, from: XCTUnwrap(transport.requestData))
        XCTAssertEqual(request.method, "issue.update")
        XCTAssertEqual(request.params["id"]?.intValue, 42)
        XCTAssertEqual(request.params["title"]?.stringValue, "Updated issue")
        XCTAssertEqual(request.params["description"]?.stringValue, "More detail")
        XCTAssertEqual(request.params["estimateMinutes"]?.intValue, 90)
    }

    func testDaemonClientBuildsIssueDeleteRequest() async throws {
        let transport = CapturingDaemonTransport(
            responseData: Data(#"{"id":"response-1","result":{"ok":true}}"#.utf8)
        )
        let client = CronaDaemonClient(transport: transport)
        _ = try await client.deleteIssue(issueID: 42)

        let request = try JSONDecoder().decode(RequestWithParamsProbe.self, from: XCTUnwrap(transport.requestData))
        XCTAssertEqual(request.method, "issue.delete")
        XCTAssertEqual(request.params["id"]?.intValue, 42)
    }

    func testDaemonClientBuildsIssueStatusChangeRequestWithNote() async throws {
        let response = issueResponseData(status: "blocked", todoForDate: nil)
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        _ = try await client.changeIssueStatus(
            issueID: 42,
            status: .blocked,
            note: "Waiting for review"
        )

        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "issue.change_status")
        XCTAssertEqual(requestProbe.params["id"]?.intValue, 42)
        XCTAssertEqual(requestProbe.params["status"]?.stringValue, "blocked")
        XCTAssertEqual(requestProbe.params["note"]?.stringValue, "Waiting for review")
    }

    func testDaemonClientBuildsSetAndClearIssueDueDateRequests() async throws {
        let setTransport = CapturingDaemonTransport(
            responseData: issueResponseData(status: "planned", todoForDate: "2026-08-02")
        )
        let setClient = CronaDaemonClient(transport: setTransport)
        _ = try await setClient.setIssueTodo(issueID: 42, date: "2026-08-02")

        var request = try XCTUnwrap(setTransport.requestData)
        var requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "issue.set_todo")
        XCTAssertEqual(requestProbe.params["id"]?.intValue, 42)
        XCTAssertEqual(requestProbe.params["date"]?.stringValue, "2026-08-02")

        let clearTransport = CapturingDaemonTransport(
            responseData: issueResponseData(status: "planned", todoForDate: nil)
        )
        let clearClient = CronaDaemonClient(transport: clearTransport)
        _ = try await clearClient.clearIssueTodo(issueID: 42)

        request = try XCTUnwrap(clearTransport.requestData)
        requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "issue.clear_todo")
        XCTAssertEqual(requestProbe.params["id"]?.intValue, 42)
    }

    func testDaemonClientBuildsHabitCompleteRequest() async throws {
        let response = """
        {"id":"response-1","result":{"id":8,"habitId":101,"date":"2026-07-13","status":"completed"}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let completion = try await client.completeHabit(habitID: 101, date: "2026-07-13")

        XCTAssertEqual(completion.id, 8)
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "habit.complete")
        XCTAssertEqual(requestProbe.params["habitId"]?.intValue, 101)
        XCTAssertEqual(requestProbe.params["date"]?.stringValue, "2026-07-13")
        XCTAssertEqual(requestProbe.params["status"]?.stringValue, "completed")
    }

    func testDaemonClientBuildsHabitFailedRequest() async throws {
        let response = """
        {"id":"response-1","result":{"id":8,"habitId":101,"date":"2026-07-13","status":"failed"}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let completion = try await client.completeHabit(
            habitID: 101,
            date: "2026-07-13",
            status: "failed"
        )

        XCTAssertEqual(completion.status, "failed")
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "habit.complete")
        XCTAssertEqual(requestProbe.params["habitId"]?.intValue, 101)
        XCTAssertEqual(requestProbe.params["date"]?.stringValue, "2026-07-13")
        XCTAssertEqual(requestProbe.params["status"]?.stringValue, "failed")
    }

    func testDaemonClientBuildsTimedHabitLogRequest() async throws {
        let response = """
        {"id":"response-1","result":{"id":8,"habitId":101,"date":"2026-07-13","status":"completed","durationMinutes":25}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let completion = try await client.completeHabit(
            habitID: 101,
            date: "2026-07-13",
            durationMinutes: 25
        )

        XCTAssertEqual(completion.durationMinutes, 25)
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "habit.complete")
        XCTAssertEqual(requestProbe.params["status"]?.stringValue, "completed")
        XCTAssertEqual(requestProbe.params["durationMinutes"]?.intValue, 25)
    }

    func testDaemonClientBuildsEndSessionRequestWithCommitMessage() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "state":"idle",
            "sessionId":"session-1",
            "issueId":303,
            "elapsedSeconds":600
          }
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let result = try await client.timerEnd(commitMessage: "Ship macOS companion end flow")

        XCTAssertEqual(result.state, "idle")
        XCTAssertEqual(result.sessionID, "session-1")
        XCTAssertEqual(result.issueID, 303)
        XCTAssertEqual(result.elapsedSeconds, 600)
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "timer.end")
        XCTAssertEqual(requestProbe.params["commitMessage"]?.stringValue, "Ship macOS companion end flow")
    }

    func testDaemonClientBuildsSingleAlertSettingPatch() async throws {
        let response = Data(#"{"id":"response-1","result":{"ok":true}}"#.utf8)
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        try await client.alertSettingPatch(
            key: "alertSoundPreset",
            value: .string("notification_ping")
        )

        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "settings.patch")
        XCTAssertEqual(requestProbe.params["key"]?.stringValue, "alertSoundPreset")
        XCTAssertEqual(requestProbe.params["value"]?.stringValue, "notification_ping")
    }

    func testDaemonClientSelectsLocalAlertSettings() async throws {
        let response = alertSettingsResponse(
            entries: """
            "other": {"alertSoundPreset":"chime","alertUrgency":"low"},
            "local": {"alertSoundPreset":"focus_gong","alertUrgency":"high"}
            """
        )
        let client = CronaDaemonClient(
            transport: CapturingDaemonTransport(responseData: response)
        )

        let settings = try await client.alertSettingsGet()

        XCTAssertEqual(settings.alertSoundPreset, .focusGong)
        XCTAssertEqual(settings.alertUrgency, .timeSensitive)
    }

    func testDaemonClientFallsBackToAvailableAlertSettingsUser() async throws {
        let response = alertSettingsResponse(
            entries: """
            "account-user": {
              "alertSoundPreset":"notification_ping",
              "alertUrgency":"low"
            }
            """
        )
        let client = CronaDaemonClient(
            transport: CapturingDaemonTransport(responseData: response)
        )

        let settings = try await client.alertSettingsGet()

        XCTAssertEqual(settings.alertSoundPreset, .notificationPing)
        XCTAssertEqual(settings.alertUrgency, .quiet)
    }

    func testDaemonClientRejectsEmptyAlertSettingsMap() async {
        let response = alertSettingsResponse(entries: "")
        let client = CronaDaemonClient(
            transport: CapturingDaemonTransport(responseData: response)
        )

        do {
            _ = try await client.alertSettingsGet()
            XCTFail("Expected an empty settings map to be rejected")
        } catch let error as CronaConnectionFailure {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func issueResponseData(status: String, todoForDate: String?) -> Data {
        let todoJSON = todoForDate.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id":"response-1",
          "result":{
            "id":42,
            "streamId":7,
            "title":"Ship context menu",
            "status":"\(status)",
            "workedSeconds":0,
            "pinnedDaily":false,
            "todoForDate":\(todoJSON)
          }
        }
        """.data(using: .utf8)!
    }

    private func alertSettingsResponse(entries: String) -> Data {
        Data(
            """
            {
              "id":"response-1",
              "result":{\(entries)}
            }
            """.utf8
        )
    }
}

private struct RequestProbe: Decodable {
    let id: String
    let method: String
}

private struct AlertDeliveryAckRequestProbe: Decodable {
    struct Params: Decodable {
        let deliveryID: String
        let notificationAccepted: Bool
        let soundAccepted: Bool
        let actionID: String?
        let actionSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case deliveryID = "deliveryId"
            case notificationAccepted
            case soundAccepted
            case actionID = "actionId"
            case actionSeconds
        }
    }

    let method: String
    let params: Params
}

private struct AlertDeliverySubscriptionProbe: Decodable {
    struct Params: Decodable {
        let clientID: String
        let notifications: Bool
        let sounds: Bool

        enum CodingKeys: String, CodingKey {
            case clientID = "clientId"
            case notifications
            case sounds
        }
    }

    let method: String
    let params: Params
}

private final class CapturingDaemonTransport: CronaDaemonTransport {
    let responseData: Data
    private(set) var requestData: Data?

    init(responseData: Data) {
        self.responseData = responseData
    }

    func send(_ request: Data) async throws -> Data {
        requestData = request
        return responseData
    }

    func openEventStream(with request: Data) async throws -> AsyncThrowingStream<CronaProtocolEvent, Error> {
        requestData = request
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
