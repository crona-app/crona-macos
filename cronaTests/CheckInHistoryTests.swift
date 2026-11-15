import XCTest

@testable import crona

@MainActor
final class CheckInHistoryTests: DaemonTestCase {
    func testHistorySearchEditingAndDeletionPreserveDailySelection() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.checkInByDate = [
            "2001-02-01": fixture("2001-02-01", notes: "Quiet morning"), "2001-02-02": fixture("2001-02-02"),
        ]
        var changedDates: [String] = []
        let day = PopoverDayModel(today: { "2001-02-03" })
        let model = CheckInHistoryModel(
            connection: connection, canMutate: { true }, onChanged: { changedDates.append($0) })
        await model.refresh()
        XCTAssertEqual(model.records.map(\.date), ["2001-02-02", "2001-02-01"])
        model.search = "quiet"
        model.reconcileSelection()
        XCTAssertEqual(model.selectedDate, "2001-02-01")
        let request = CronaDailyCheckInUpsertRequest(
            date: "2001-02-01", mood: 4, energy: 5,
            sleepHours: nil, sleepScore: nil, screenTimeMinutes: nil, notes: "Edited")
        let saved = await model.save(request, originalDate: "2001-02-01")
        XCTAssertTrue(saved)
        XCTAssertEqual(changedDates, ["2001-02-01"])
        XCTAssertEqual(day.selectedDate, "2001-02-03")
        model.search = ""
        model.selectedDate = "2001-02-02"
        await model.delete(date: "2001-02-02")
        XCTAssertEqual(model.selectedDate, "2001-02-01")
        XCTAssertEqual(model.records.count, 1)
        XCTAssertEqual(day.selectedDate, "2001-02-03")
    }

    func testHistoryRejectsChangingDateAndProtectedRestMutations() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        var canMutate = false
        let model = CheckInHistoryModel(connection: connection, canMutate: { canMutate }, onChanged: { _ in })
        let request = CronaDailyCheckInUpsertRequest(
            date: "2001-02-01", mood: 4, energy: 5,
            sleepHours: nil, sleepScore: nil, screenTimeMinutes: nil, notes: nil)
        let protectedSave = await model.save(request, originalDate: request.date)
        XCTAssertFalse(protectedSave)
        await model.delete(date: request.date)
        XCTAssertFalse(transport.methods.contains("checkin.delete"))
        canMutate = true
        let wrongDate = await model.save(request, originalDate: "2001-02-02")
        XCTAssertFalse(wrongDate)
        transport.failCheckIn = true
        let failed = await model.save(request, originalDate: request.date)
        XCTAssertFalse(failed)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isSaving)
    }

    func testSupersededHistoryResponseCannotOverwriteNewerLoad() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let model = CheckInHistoryModel(connection: connection, canMutate: { true }, onChanged: { _ in })
        transport.checkInByDate = ["2001-02-01": fixture("2001-02-01")]
        transport.suspendCheckInRange = true
        let older = Task { await model.refresh() }
        await waitForIssueCreator { transport.methods.contains("checkin.range") }
        transport.suspendCheckInRange = false
        transport.checkInByDate = ["2001-02-02": fixture("2001-02-02")]
        await model.refresh()
        transport.resumeCheckInRange()
        await older.value
        XCTAssertEqual(model.records.map(\.date), ["2001-02-02"])
        XCTAssertFalse(model.isLoading)
    }

    private func fixture(_ date: String, notes: String = "") -> [String: Any] {
        ["date": date, "mood": 3, "energy": 4, "notes": notes]
    }
}
