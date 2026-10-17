import XCTest
@testable import crona

@MainActor
final class DaemonProtocolTests: DaemonTestCase {
    func testManualSessionRequestEncodesDaemonWireKeys() throws {
        let request = CronaManualSessionLogRequest(
            issueID: 42,
            date: "2026-08-16",
            workDurationSeconds: 5_400,
            breakDurationSeconds: 900,
            startTime: "09:00",
            endTime: "10:45",
            commitMessage: "Manual catch-up",
            notes: "Forgot to start timer"
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]

        XCTAssertEqual(object["issueId"] as? Int, 42)
        XCTAssertEqual(object["workDurationSeconds"] as? Int, 5_400)
        XCTAssertEqual(object["breakDurationSeconds"] as? Int, 900)
        XCTAssertEqual(object["commitMessage"] as? String, "Manual catch-up")
        XCTAssertEqual(object["notes"] as? String, "Forgot to start timer")
    }

    func testDailyCheckInDecodesOptionalWellbeingFields() throws {
        let data = Data(#"{"date":"2026-08-13","mood":4,"energy":3,"sleepHours":7.5,"sleepScore":82,"screenTimeMinutes":95,"notes":"Steady day","createdAt":"now","updatedAt":"now"}"#.utf8)
        let checkIn = try JSONDecoder().decode(CronaDailyCheckIn.self, from: data)

        XCTAssertEqual(checkIn.mood, 4)
        XCTAssertEqual(checkIn.energy, 3)
        XCTAssertEqual(checkIn.sleepHours, 7.5)
        XCTAssertEqual(checkIn.sleepScore, 82)
        XCTAssertEqual(checkIn.screenTimeMinutes, 95)
        XCTAssertEqual(checkIn.notes, "Steady day")
    }

    func testAlertDeliveryDecodesWithoutActions() throws {
        let event = try JSONDecoder().decode(
            CronaProtocolEvent.self,
            from: """
            {
              "type":"alert.delivery",
              "payload":{
                "id":"alert-1",
                "alert":{
                  "kind":"daily_plan.reminder",
                  "title":"Plan the day",
                  "body":"Choose today's priorities.",
                  "urgency":"normal",
                  "iconEnabled":true,
                  "playSound":false
                },
                "deliverNotification":true,
                "playSound":false
              }
            }
            """.data(using: .utf8)!
        )

        let delivery = try event.decodePayload(CronaAlertDelivery.self)

        XCTAssertEqual(delivery.id, "alert-1")
        XCTAssertEqual(delivery.alert.kind, "daily_plan.reminder")
        XCTAssertNil(delivery.actions)
    }

    func testAlertDeliveryDecodesBreakDeferralAction() throws {
        let event = try JSONDecoder().decode(
            CronaProtocolEvent.self,
            from: """
            {
              "type":"alert.delivery",
              "payload":{
                "id":"alert-break",
                "alert":{"kind":"timer.break_deferral_warning","title":"Keep working","body":"","urgency":"high","iconEnabled":true,"playSound":false},
                "deliverNotification":true,
                "playSound":false,
                "actions":[{"id":"timer.defer_break","title":"Keep Working","sessionId":"session-1","suggestedSeconds":60}]
              }
            }
            """.data(using: .utf8)!
        )

        let action = try XCTUnwrap(event.decodePayload(CronaAlertDelivery.self).actions?.first)
        XCTAssertEqual(action.id, "timer.defer_break")
        XCTAssertEqual(action.sessionID, "session-1")
        XCTAssertEqual(action.suggestedSeconds, 60)
    }

    func testAlertDeliveryDecodesExportActionPath() throws {
        let event = try JSONDecoder().decode(
            CronaProtocolEvent.self,
            from: """
            {
              "type":"alert.delivery",
              "payload":{
                "id":"alert-2",
                "alert":{
                  "kind":"export.completed",
                  "title":"Export ready",
                  "body":"Open the file or reveal it in Finder.",
                  "urgency":"low",
                  "iconEnabled":true,
                  "playSound":false
                },
                "deliverNotification":true,
                "playSound":false,
                "actions":[
                  {
                    "id":"export.open",
                    "title":"Open File",
                    "path":"/tmp/report.md"
                  }
                ]
              }
            }
            """.data(using: .utf8)!
        )

        let delivery = try event.decodePayload(CronaAlertDelivery.self)

        XCTAssertEqual(delivery.alert.kind, "export.completed")
        XCTAssertEqual(delivery.actions?.first?.path, "/tmp/report.md")
    }

    func testOptionalActiveContextDecodesNull() throws {
        let response = """
        {"id":"response-1","result":null}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaActiveContext?>.self, from: response)

        XCTAssertNil(decoded.result ?? nil)
    }

    func testActiveContextDecodesDaemonWireKeys() throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "userId":"local",
            "deviceId":"macbook",
            "repoId":101,
            "repoName":"crona",
            "streamId":202,
            "streamName":"desktop",
            "issueId":303,
            "issueTitle":"Ship companion",
            "updatedAt":"2026-07-13T06:30:00Z"
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaActiveContext>.self, from: response)
        let context = try XCTUnwrap(decoded.result)

        XCTAssertEqual(context.userID, "local")
        XCTAssertEqual(context.deviceID, "macbook")
        XCTAssertEqual(context.repoID, 101)
        XCTAssertEqual(context.repoName, "crona")
        XCTAssertEqual(context.streamID, 202)
        XCTAssertEqual(context.streamName, "desktop")
        XCTAssertEqual(context.issueID, 303)
        XCTAssertEqual(context.issueTitle, "Ship companion")
    }

    func testSparseTimerStateDecodesIdleState() throws {
        let response = """
        {"id":"response-1","result":{"state":"idle"}}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaTimerState>.self, from: response)

        XCTAssertEqual(decoded.result?.state, "idle")
        XCTAssertNil(decoded.result?.elapsedSeconds)
    }

    func testTimerStateDecodesDaemonWireKeys() throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "state":"running",
            "sessionId":"session-1",
            "sessionStartTime":"2026-07-13T06:00:00Z",
            "issueId":303,
            "segmentType":"work",
            "segmentStartTime":"2026-07-13T06:05:00Z",
            "segmentElapsedOffsetSeconds":15,
            "nextSegmentType":"break",
            "elapsedSeconds":600
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaTimerState>.self, from: response)
        let state = try XCTUnwrap(decoded.result)

        XCTAssertEqual(state.sessionID, "session-1")
        XCTAssertEqual(state.issueID, 303)
        XCTAssertEqual(state.segmentType, "work")
        XCTAssertEqual(state.segmentElapsedOffsetSeconds, 15)
        XCTAssertEqual(state.elapsedSeconds, 600)
    }

    func testTimerStateDecodesExplicitHardLimitKind() throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "state":"running",
            "sessionId":"session-1",
            "hardLimitActive":true,
            "hardLimitKind":"countdown",
            "hardLimitTotalSeconds":1500
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaTimerState>.self, from: response)
        let state = try XCTUnwrap(decoded.result)
        let snapshot = TimerSnapshot.from(state)

        XCTAssertEqual(state.hardLimitKind, "countdown")
        XCTAssertEqual(snapshot.hardLimitKind, .countdown)
        XCTAssertEqual(TimerPresentation.from(snapshot).mode, .timer)
    }

    func testMissingAndUnknownHardLimitKindsNormalizeToPomodoro() throws {
        for rawKind in [nil, "future-kind"] as [String?] {
            let snapshot = TimerSnapshot(
                state: "running",
                sessionID: "session-1",
                hardLimitActive: true,
                hardLimitKind: CronaTimerHardLimitKind.normalized(rawKind),
                hardLimitTotalSeconds: 1500,
                hardLimitWorkSeconds: 1500,
                isConnected: true
            )

            XCTAssertEqual(snapshot.hardLimitKind, .pomodoro)
            XCTAssertEqual(TimerPresentation.from(snapshot).mode, .pomodoro)
        }
    }

    func testHabitDailyItemDecodesDueHabitPayload() throws {
        let response = """
        {
          "id":"response-1",
          "result":[{
            "id":101,
            "streamId":202,
            "name":"Stretch",
            "description":"Move a bit",
            "scheduleType":"daily",
            "weekdays":[],
            "targetMinutes":15,
            "active":true,
            "repoId":1,
            "repoName":"Crona",
            "streamName":"Wellbeing",
            "status":"completed",
            "completed":true,
            "completionId":44,
            "completionDate":"2026-07-13",
            "durationMinutes":12
          }]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<[CronaHabitDailyItem]>.self, from: response)
        let item = try XCTUnwrap(decoded.result?.first)

        XCTAssertEqual(item.id, 101)
        XCTAssertEqual(item.name, "Stretch")
        XCTAssertEqual(item.repoName, "Crona")
        XCTAssertEqual(item.streamName, "Wellbeing")
        XCTAssertEqual(item.status, "completed")
        XCTAssertEqual(item.durationMinutes, 12)
        XCTAssertEqual(item.targetMinutes, 15)
    }

    func testCountdownStartEncodingOmitsPomodoroCadence() throws {
        let issue = DailyFocusIssue(
            id: 33,
            streamID: 22,
            title: "Issue",
            status: "planned",
            estimateMinutes: nil,
            workedSeconds: 0,
            todoForDate: nil
        )
        let state = FocusStartConfigState(
            mode: .timer,
            countdownChoice: .custom,
            customCountdownMinutes: 45
        )

        let encoded = try JSONEncoder().encode(state.startRequest(for: issue))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(object["hardLimitKind"] as? String, "countdown")
        XCTAssertEqual(object["hardLimitTotalSeconds"] as? Int, 45 * 60)
        XCTAssertNil(object["hardLimitWorkSeconds"])
        XCTAssertNil(object["hardLimitBreakSeconds"])
        XCTAssertNil(object["hardLimitLongBreakSeconds"])
        XCTAssertNil(object["hardLimitCyclesBeforeLongBreak"])
    }

    func testIssueStatusNoteRequirementsMirrorDaemonContract() {
        XCTAssertTrue(CronaIssueStatus.blocked.requiresNote)
        XCTAssertTrue(CronaIssueStatus.abandoned.requiresNote)
        XCTAssertFalse(CronaIssueStatus.done.requiresNote)
        XCTAssertEqual(CronaIssueStatus.inReview.notePrompt, "Review note (optional)")
        XCTAssertNil(CronaIssueStatus.planned.notePrompt)
    }

    func testProtocolEventExtractsSessionIDFromPayload() throws {
        let data = """
        {"type":"session.ended","payload":{"sessionId":"session-42"}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(CronaProtocolEvent.self, from: data)

        XCTAssertEqual(event.sessionID, "session-42")
    }

    func testHealthDecodesDaemonCurrentDateAndTimezone() throws {
        let data = """
        {"status":"ok","db":true,"ok":1,"uptime":42.5,"currentDate":"2026-07-29","timezone":"Asia/Kolkata"}
        """.data(using: .utf8)!

        let health = try JSONDecoder().decode(CronaHealth.self, from: data)

        XCTAssertEqual(health.currentDate, "2026-07-29")
        XCTAssertEqual(health.timezone, "Asia/Kolkata")
    }

    func testDayBoundaryScheduleDecodesIntegerWeekdayKeys() throws {
        let data = """
        {"enabled":true,"defaultTime":"08:30","weekdayOverrides":{"1":"09:00","7":"10:15"}}
        """.data(using: .utf8)!

        let schedule = try JSONDecoder().decode(CronaDayBoundarySchedule.self, from: data)

        XCTAssertTrue(schedule.isValid)
        XCTAssertEqual(schedule.weekdayOverrides[1], "09:00")
        XCTAssertEqual(schedule.weekdayOverrides[7], "10:15")
    }

    func testDayBoundaryEventDecodesLogicalDateAndOccurrence() throws {
        let data = """
        {"type":"day.start","payload":{"kind":"start","dateBefore":"2026-07-28","dateAfter":"2026-07-29","effectiveLocalTime":"2026-07-29T08:30:00+05:30","effectiveUtcTime":"2026-07-29T03:00:00Z","timezone":"Asia/Kolkata","occurrenceId":"occurrence-1","logicalDate":"2026-07-29"}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(CronaProtocolEvent.self, from: data)
        let payload = try event.decodePayload(CronaDayBoundaryEventPayload.self)

        XCTAssertEqual(event.type, "day.start")
        XCTAssertEqual(payload.logicalDate, "2026-07-29")
        XCTAssertEqual(payload.occurrenceID, "occurrence-1")
        XCTAssertEqual(payload.effectiveUTCTime, "2026-07-29T03:00:00Z")
    }

    func testDayBoundaryScheduleEncodingPreservesDaemonWireShape() throws {
        let schedule = CronaDayBoundarySchedule(
            enabled: true,
            defaultTime: "17:30",
            weekdayOverrides: [1: "16:30"]
        )

        let encoded = try JSONEncoder().encode(schedule)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(object["enabled"] as? Bool, true)
        XCTAssertEqual(object["defaultTime"] as? String, "17:30")
        let overrides = try XCTUnwrap(object["weekdayOverrides"] as? [String: String])
        XCTAssertEqual(overrides["1"], "16:30")
    }

    func testQuickExtendRequestUsesSecondsNotSessions() {
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            issueID: 10,
            segmentType: "work",
            nextSegmentType: nil,
            readySegmentType: nil,
            elapsedSeconds: 600,
            sessionStartTime: nil,
            segmentStartTime: nil,
            hardLimitActive: true,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 1800,
            hardLimitRemainingSeconds: 1200,
            hardLimitWorkSeconds: 1500,
            hardLimitBreakSeconds: 300,
            hardLimitLongBreakSeconds: 900,
            hardLimitCyclesBeforeLongBreak: 4,
            snapshotAppliedAt: Date(),
            isConnected: true
        )

        let request = CompanionAppState.buildQuickExtendRequest(snapshot: snapshot, additionalSeconds: 300)

        XCTAssertEqual(request?.additionalSeconds, 300)
        XCTAssertEqual(request?.additionalSessions, 0)
        XCTAssertNil(request?.hardLimitTotalSeconds)
        XCTAssertNil(request?.hardLimitWorkSeconds)
        XCTAssertNil(request?.hardLimitBreakSeconds)
    }

    func testQuickExtendRequestRejectsZeroSeconds() {
        let request = CompanionAppState.buildQuickExtendRequest(snapshot: TimerSnapshot(), additionalSeconds: 0)
        XCTAssertNil(request)
    }
}
