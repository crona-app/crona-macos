import XCTest
@testable import crona

@MainActor
final class CronaProjectTests: XCTestCase {
    func testCoreLinksBuildOnRepoOwner() {
        let base = "https://github.com/\(CronaProject.repoOwner)/crona"
        XCTAssertEqual(CronaProject.coreRepoURL, base)
        XCTAssertEqual(CronaProject.docsURL, "\(base)/tree/main/docs")
        XCTAssertEqual(CronaProject.discussionsURL, "\(base)/discussions")
    }

    /// The release feed is baked into installed apps, so it must move with the owner deliberately.
    func testReleaseFeedURLSharesRepoOwner() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/Info-Release.plist")
        let values = try XCTUnwrap(NSDictionary(contentsOf: plist))
        let feed = try XCTUnwrap(values["SUFeedURL"] as? String)
        XCTAssertEqual(feed, "https://\(CronaProject.repoOwner).github.io/crona-macos/appcast.xml")
    }
}
