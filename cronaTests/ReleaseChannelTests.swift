import XCTest
@testable import crona

@MainActor
final class ReleaseChannelTests: DaemonTestCase {
    func testAppReleaseChannelInfersBetaFromPrereleaseVersion() {
        XCTAssertEqual(AppReleaseChannel.inferred(from: "2.1.0-beta.3"), .beta)
        XCTAssertEqual(AppReleaseChannel.inferred(from: "2.1.0"), .stable)
    }

    func testAppReleaseChannelPrefersExplicitBundleMetadata() {
        XCTAssertEqual(
            AppReleaseChannel.resolved(configuredValue: "beta", version: "2.1.0"),
            .beta
        )
        XCTAssertEqual(
            AppReleaseChannel.resolved(configuredValue: "stable", version: "2.1.0-beta.3"),
            .stable
        )
        XCTAssertEqual(
            AppReleaseChannel.resolved(configuredValue: nil, version: "2.1.0-beta.3"),
            .beta
        )
    }

    func testAppUpdateChannelPersistsWithoutStartingSparkle() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        let service = AppUpdateService(preferences: preferences, enabled: false)

        service.setChannel(.beta)

        XCTAssertEqual(service.selectedChannel, .beta)
        XCTAssertEqual(PreferencesService(defaults: defaults).preferences.appUpdateChannel, .beta)
    }
}
