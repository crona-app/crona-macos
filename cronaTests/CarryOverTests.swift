import AppKit
import SwiftUI
import XCTest
@testable import crona

@MainActor
final class CarryOverTests: DaemonTestCase {
    func testCarriedSemanticColorIsLavender() throws {
        let color = try XCTUnwrap(NSColor(PopupVisualTheme.semantic(.carried)).usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, 0.686, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, 0.529, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, 1.0, accuracy: 0.01)
    }

    func testBadgeText() {
        XCTAssertNil(CronaCarryPresentation.badgeText(for: nil))
        XCTAssertEqual(CronaCarryPresentation.badgeText(for: DailyFocusCarry(count: 1, stalled: false, fromDate: nil)), "Carried ×1")
        XCTAssertEqual(CronaCarryPresentation.badgeText(for: DailyFocusCarry(count: 3, stalled: false, fromDate: nil)), "Carried ×3")
        XCTAssertEqual(CronaCarryPresentation.badgeText(for: DailyFocusCarry(count: 2, stalled: true, fromDate: nil)), "Stalled")
        XCTAssertEqual(CronaCarryPresentation.badgeText(for: DailyFocusCarry(count: 0, stalled: true, fromDate: nil)), "Stalled")
    }

    private func focusIssue(_ id: Int64, _ title: String = "Fix sync") -> DailyFocusIssue {
        DailyFocusIssue(id: id, streamID: 7, title: title, status: "planned", estimateMinutes: nil,
            workedSeconds: 0, todoForDate: nil)
    }

    private func makeModel(changes: (() -> Void)? = nil) async throws -> (CarryOverModel, IssueCreatorTestTransport) {
        let (connection, transport) = try await issueCreatorConnection()
        addTeardownBlock { connection.stop() }
        let model = CarryOverModel(
            daemonConnection: connection, onChanged: { changes?() }, undoWindow: .milliseconds(50))
        return (model, transport)
    }

    private func count(_ transport: IssueCreatorTestTransport, _ method: String) -> Int {
        transport.methods.filter { $0 == method }.count
    }

    func testCarrySendsIssueCarryAndOffersUndo() async throws {
        let (model, transport) = try await makeModel()
        await model.carry(focusIssue(4))
        XCTAssertEqual(transport.requests.last { $0.method == "issue.carry" }?.params["id"]?.intValue, 4)
        XCTAssertEqual(model.undoOffer, CarryUndoOffer(issueID: 4, title: "Fix sync"))
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.inFlightIssueID)
    }

    func testCarryCallsOnChanged() async throws {
        var changed = 0
        let (model, _) = try await makeModel { changed += 1 }
        await model.carry(focusIssue(4))
        XCTAssertEqual(changed, 1)
    }

    func testCarryIgnoredWhileInFlight() async throws {
        let (model, transport) = try await makeModel()
        transport.suspendCarry = true
        let first = Task { await model.carry(focusIssue(4)) }
        await waitForIssueCreator { model.inFlightIssueID == 4 }
        await model.carry(focusIssue(5))
        transport.resumeCarry()
        await first.value
        XCTAssertEqual(count(transport, "issue.carry"), 1)
    }

    func testUndoSendsCarryUndoAndClearsOffer() async throws {
        let (model, transport) = try await makeModel()
        await model.carry(focusIssue(4))
        await model.undo()
        XCTAssertEqual(transport.requests.last { $0.method == "issue.carry.undo" }?.params["id"]?.intValue, 4)
        XCTAssertNil(model.undoOffer)
    }

    func testUndoOfferExpiresAndUndoDoesNothing() async throws {
        let (model, transport) = try await makeModel()
        await model.carry(focusIssue(4))
        await waitForIssueCreator { model.undoOffer == nil }
        await model.undo()
        XCTAssertEqual(count(transport, "issue.carry.undo"), 0)
    }

    func testCarryFailureSetsErrorWithoutOffer() async throws {
        let (model, transport) = try await makeModel()
        transport.failCarry = true
        await model.carry(focusIssue(4))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.undoOffer)
    }

    func testUndoFailureSetsErrorAndClearsOffer() async throws {
        let (model, transport) = try await makeModel()
        await model.carry(focusIssue(4))
        transport.failCarryUndo = true
        await model.undo()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.undoOffer)
    }

    func testSecondCarryReplacesUndoOffer() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let model = CarryOverModel(daemonConnection: connection, onChanged: {}, undoWindow: .milliseconds(150))
        await model.carry(focusIssue(4, "A"))
        try await Task.sleep(for: .milliseconds(100))
        await model.carry(focusIssue(5, "B"))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.undoOffer, CarryUndoOffer(issueID: 5, title: "B"))
    }

    func testUndoCarryByIDSendsUndo() async throws {
        let (model, transport) = try await makeModel()
        await model.undoCarry(issueID: 9)
        XCTAssertEqual(transport.requests.last { $0.method == "issue.carry.undo" }?.params["id"]?.intValue, 9)
        XCTAssertNil(model.errorMessage)
    }

    func testUndoMessage() {
        XCTAssertEqual(CronaCarryPresentation.undoMessage(title: "Fix sync"), "Carried \u{201C}Fix sync\u{201D} to tomorrow")
    }
}
