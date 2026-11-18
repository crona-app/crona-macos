import XCTest
@testable import crona

@MainActor
final class GlobalShortcutsTests: DaemonTestCase {
    private func binding(_ key: UInt32) -> SettingsShortcut {
        SettingsShortcut(keyCode: key, modifiers: 256, display: "Command \(key)")
    }

    func testAssignmentFailurePreservesPreviousBindingAndRegistration() {
        let preferences = isolatedPreferences()
        let registry = FakeShortcutRegistry()
        let model = GlobalShortcutsModel(preferences: preferences, registry: registry, perform: { _ in })
        XCTAssertTrue(model.assign(binding(1), to: .show))
        registry.fail = true
        XCTAssertFalse(model.assign(binding(2), to: .show))
        XCTAssertEqual(preferences.preferences.globalShortcuts["show"], binding(1))
        XCTAssertEqual(registry.bindings.count, 1)
        XCTAssertEqual(registry.bindings.values.first, binding(1))
        XCTAssertNotNil(model.errors["show"])
    }

    func testDuplicateReportsActionAndClearAllowsReassignment() {
        let model = GlobalShortcutsModel(preferences: isolatedPreferences(), registry: FakeShortcutRegistry(), perform: { _ in })
        XCTAssertTrue(model.assign(binding(1), to: .show))
        XCTAssertFalse(model.assign(binding(1), to: .createIssue))
        XCTAssertTrue(model.errors["createIssue"]?.contains("Show Crona") == true)
        XCTAssertTrue(model.assign(nil, to: .show))
        XCTAssertTrue(model.assign(binding(1), to: .createIssue))
        XCTAssertFalse(model.assign(SettingsShortcut(keyCode: 2, modifiers: 512, display: "Shift"), to: .show))
    }

    func testHeldKeysRecordingAndOverlappingActionsAreSuppressed() async {
        let registry = FakeShortcutRegistry()
        var actions: [GlobalShortcutAction] = []
        var continuation: CheckedContinuation<Void, Never>?
        let model = GlobalShortcutsModel(preferences: isolatedPreferences(), registry: registry) { action in
            actions.append(action)
            await withCheckedContinuation { continuation = $0 }
        }
        model.assign(binding(1), to: .show)
        let id = registry.bindings.keys.first!
        model.isRecording = true
        registry.onEvent?(id, false)
        await settleAsyncTasks()
        XCTAssertTrue(actions.isEmpty)
        model.isRecording = false
        registry.onEvent?(id, false)
        await settleAsyncTasks()
        registry.onEvent?(id, false)
        registry.onEvent?(id, true)
        registry.onEvent?(id, false)
        await settleAsyncTasks()
        XCTAssertEqual(actions, [.show])
        continuation?.resume()
        await settleAsyncTasks()
        model.stop()
        XCTAssertTrue(registry.bindings.isEmpty)
    }

    func testLegacyMigrationAndClearingSurviveRoundTrip() throws {
        let legacy = try JSONSerialization.data(withJSONObject: ["settingsShortcut": ["keyCode": 1, "modifiers": 256, "display": "Command"]])
        var preferences = try JSONDecoder().decode(CompanionPreferences.self, from: legacy)
        XCTAssertNotNil(preferences.globalShortcuts["settings"])
        preferences.settingsShortcut = nil
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(CompanionPreferences.self, from: encoded)
        XCTAssertNil(decoded.settingsShortcut)
        let explicitEmpty = try JSONSerialization.data(withJSONObject: ["globalShortcuts": [:], "settingsShortcut": ["keyCode": 1, "modifiers": 256, "display": "Command"]])
        XCTAssertNil(try JSONDecoder().decode(CompanionPreferences.self, from: explicitEmpty).settingsShortcut)
    }

    func testReloadOnlyRegistersChangedBindingsAndReportsStartupFailure() {
        let preferences = isolatedPreferences()
        preferences.preferences.globalShortcuts = ["show": binding(1)]
        let registry = FakeShortcutRegistry()
        registry.fail = true
        let model = GlobalShortcutsModel(preferences: preferences, registry: registry, perform: { _ in })
        model.reload()
        XCTAssertNotNil(model.errors["show"])
        registry.fail = false
        model.reload()
        let original = registry.bindings
        model.reload()
        XCTAssertEqual(original, registry.bindings)
        XCTAssertNil(model.errors["show"])
    }

    func testUnavailableTimerActionsDoNotSendCommands() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await state.timerService.refresh()
        await state.performGlobalShortcut(.pauseResume)
        await state.performGlobalShortcut(.endSession)
        XCTAssertFalse(transport.methods.contains("timer.pause"))
        XCTAssertFalse(transport.methods.contains("timer.resume"))
        XCTAssertFalse(state.endSession.isSheetPresented)
    }

    func testCreatorDraftAndFocusSetupArePreserved() async throws {
        let (connection, _) = try await issueCreatorConnection()
        let state = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await state.performGlobalShortcut(.createIssue)
        state.issueCreator.title = "Keep this draft"
        await state.performGlobalShortcut(.createIssue)
        XCTAssertEqual(state.issueCreator.title, "Keep this draft")
        await state.performGlobalShortcut(.startFocus)
        XCTAssertFalse(state.isAdhocStartSelected)
        XCTAssertTrue(state.issueCreator.isPresented)
        state.issueCreator.cancel()
        await waitForIssueCreator { !state.issueCreator.isPresented }
        await state.performGlobalShortcut(.startFocus)
        XCTAssertTrue(state.isAdhocStartSelected)
        await state.performGlobalShortcut(.createIssue)
        XCTAssertFalse(state.issueCreator.isPresented)
        XCTAssertTrue(state.isAdhocStartSelected)
    }
}

@MainActor
private final class FakeShortcutRegistry: ShortcutRegistering {
    var onEvent: ((UInt32, Bool) -> Void)?
    var bindings: [UInt32: SettingsShortcut] = [:]
    var fail = false
    func register(_ binding: SettingsShortcut, id: UInt32) throws {
        if fail { throw SettingsShortcutService.RegistrationError() }
        bindings[id] = binding
    }
    func unregister(id: UInt32) { bindings[id] = nil }
}
