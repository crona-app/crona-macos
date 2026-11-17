import XCTest
@testable import crona

@MainActor
final class WellbeingTimingDraftTests: XCTestCase {
    func testLoadingCheckInPreservesIndividualMinutes() {
        let entry = CronaDailyCheckIn(date: "2026-11-17", mood: 4, energy: 3,
            sleepHours: 7.3, sleepScore: 87, screenTimeMinutes: 133,
            notes: nil, createdAt: nil, updatedAt: nil)
        let draft = WellbeingTimingDraft(entry: entry)
        XCTAssertEqual(draft.sleepDuration, "7h18m")
        XCTAssertEqual(draft.screenDuration, "2h13m")
        XCTAssertEqual(draft.sleepScoreText, "87")
        XCTAssertEqual(draft.sleepHours, 7.3)
        XCTAssertEqual(draft.screenTimeMinutes, 133)
        XCTAssertEqual(draft.sleepScore, 87)
        XCTAssertNil(draft.validationError)
    }

    func testDurationFieldsAcceptAnyMinuteAndRejectInvalidDailyValues() {
        var draft = WellbeingTimingDraft()
        draft.hasSleepDuration = true
        draft.sleepDuration = "5h07m"
        XCTAssertEqual(draft.sleepHours, 307.0 / 60)
        for text in ["", "oops", "-1m", "24h1m"] {
            draft.sleepDuration = text
            XCTAssertNotNil(draft.validationError, text)
        }
        draft.sleepDuration = "24h0m"
        XCTAssertNil(draft.validationError)
        draft.hasScreenTime = true
        draft.screenDuration = "47m"
        XCTAssertEqual(draft.screenTimeMinutes, 47)
        draft.screenDuration = "24h1m"
        XCTAssertNotNil(draft.validationError)
        draft.hasScreenTime = false
        XCTAssertNil(draft.validationError)
        XCTAssertNil(draft.screenTimeMinutes)
    }

    func testSleepScoreCanBeEnteredDirectlyAndMustBeWithinRange() {
        var draft = WellbeingTimingDraft()
        draft.hasSleepScore = true
        for score in [0, 43, 80, 100] {
            draft.sleepScoreText = String(score)
            XCTAssertEqual(draft.sleepScore, score)
            XCTAssertNil(draft.validationError)
        }
        for text in ["", "101", "-1", "80.5", "abc"] {
            draft.sleepScoreText = text
            XCTAssertNil(draft.sleepScore)
            XCTAssertNotNil(draft.validationError)
        }
        draft.hasSleepScore = false
        XCTAssertNil(draft.validationError)
    }

    func testDurationInputRejectsOverflowWithoutTrapping() {
        for text in ["inf", "1e99", "999999999999999999999h", String(Int.max)] {
            XCTAssertNil(DurationInput.minutes(text), text)
        }
        XCTAssertEqual(DurationInput.minutes("1h07m"), 67)
    }
}
