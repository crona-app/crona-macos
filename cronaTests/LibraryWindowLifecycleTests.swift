import AppKit
import XCTest
@testable import crona

@MainActor
final class LibraryWindowLifecycleTests: DaemonTestCase {
    func testCloseReleasesContentAndReopenKeepsNavigation() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        var closes = 0
        let controller = LibraryWindowController(windowService: state.windowService) { closes += 1 }
        controller.show(appState: state)
        let first = try XCTUnwrap(NSApp.windows.first { $0.title == "Crona Library" && $0.isVisible })
        XCTAssertNotNil(first.contentViewController)
        let destination = state.libraryNavigation.destination
        first.close()
        XCTAssertNil(first.contentViewController)
        XCTAssertEqual(closes, 1)
        controller.show(appState: state)
        let second = try XCTUnwrap(NSApp.windows.first { $0.title == "Crona Library" && $0.isVisible })
        XCTAssertFalse(first === second)
        XCTAssertNotNil(second.contentViewController)
        XCTAssertEqual(state.libraryNavigation.destination, destination)
        second.close()
        XCTAssertEqual(closes, 2)
    }
}
