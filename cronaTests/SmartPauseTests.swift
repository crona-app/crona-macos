import Combine
import XCTest
@testable import crona

@MainActor
final class SmartPauseTests: DaemonTestCase {
    func testSmartPauseEligibilityOnlyAllowsRunningStopwatch() {
        let stopwatch = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        XCTAssertTrue(SmartPauseService.isEligibleStopwatch(stopwatch))

        var paused = stopwatch
        paused.state = "paused"
        XCTAssertFalse(SmartPauseService.isEligibleStopwatch(paused))

        var pomodoro = stopwatch
        pomodoro.hardLimitActive = true
        pomodoro.hardLimitKind = .pomodoro
        XCTAssertFalse(SmartPauseService.isEligibleStopwatch(pomodoro))

        var disconnected = stopwatch
        disconnected.isConnected = false
        XCTAssertFalse(SmartPauseService.isEligibleStopwatch(disconnected))
    }

    func testSmartPauseDeduplicatesConditionsAndResumesAfterAllClear() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        preferences.preferences.smartPauseEnabled = true
        preferences.preferences.smartPauseOnInactivity = false

        let timer = SmartPauseTimerController()
        timer.snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        let service = SmartPauseService(
            preferences: preferences,
            timerController: timer,
            systemMonitor: SmartPauseMonitor(),
            idleTimeProvider: SmartPauseIdleProvider(seconds: 0)
        )
        service.start()
        defer { service.stop() }

        service.handleSystemEvent(.sessionResigned)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.pauseCount, 1)
        XCTAssertEqual(timer.snapshot.state, "paused")

        service.handleSystemEvent(.screensSlept)
        service.handleSystemEvent(.sessionBecameActive)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.resumeCount, 0)

        service.handleSystemEvent(.screensWoke)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.resumeCount, 1)
        XCTAssertEqual(timer.snapshot.state, "running")
    }

    func testDisablingSmartPauseDoesNotResumeOwnedPause() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        preferences.preferences.smartPauseEnabled = true
        preferences.preferences.smartPauseOnInactivity = false

        let timer = SmartPauseTimerController()
        timer.snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        let service = SmartPauseService(
            preferences: preferences,
            timerController: timer,
            systemMonitor: SmartPauseMonitor(),
            idleTimeProvider: SmartPauseIdleProvider(seconds: 0)
        )
        service.start()
        defer { service.stop() }

        service.handleSystemEvent(.sessionResigned)
        await settleSmartPauseTasks()
        preferences.preferences.smartPauseEnabled = false
        service.handleSystemEvent(.sessionBecameActive)
        await settleSmartPauseTasks()

        XCTAssertEqual(timer.pauseCount, 1)
        XCTAssertEqual(timer.resumeCount, 0)
        XCTAssertEqual(timer.snapshot.state, "paused")
    }

    func testSmartPauseUsesIdleThresholdAndResumesOnInput() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        preferences.preferences.smartPauseEnabled = true
        preferences.preferences.smartPauseOnLock = false
        preferences.preferences.smartPauseOnDisplaySleep = false
        preferences.preferences.smartPauseOnInactivity = true
        preferences.preferences.smartPauseIdleSeconds = 30

        let timer = SmartPauseTimerController()
        timer.snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        let idleProvider = SmartPauseMutableIdleProvider(seconds: 31)
        let service = SmartPauseService(
            preferences: preferences,
            timerController: timer,
            systemMonitor: SmartPauseMonitor(),
            idleTimeProvider: idleProvider
        )
        service.start()
        defer { service.stop() }

        await settleSmartPauseTasks()
        XCTAssertEqual(timer.pauseCount, 1)

        idleProvider.seconds = 0
        service.evaluateIdleState()
        await settleSmartPauseTasks()

        XCTAssertEqual(timer.resumeCount, 1)
        XCTAssertEqual(timer.snapshot.state, "running")
    }

    func testSmartPauseLockPausesImmediatelyAndReportsAutomaticResume() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        preferences.preferences.smartPauseEnabled = true
        preferences.preferences.smartPauseOnLock = true
        preferences.preferences.smartPauseOnDisplaySleep = false
        preferences.preferences.smartPauseOnInactivity = true
        preferences.preferences.smartPauseIdleSeconds = 600

        let timer = SmartPauseTimerController()
        timer.snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        var resumedSessionID: String?
        let service = SmartPauseService(
            preferences: preferences,
            timerController: timer,
            systemMonitor: SmartPauseMonitor(),
            idleTimeProvider: SmartPauseIdleProvider(seconds: 0)
        )
        service.setAutomaticResumeHandler { snapshot in resumedSessionID = snapshot.sessionID }
        service.start()
        defer { service.stop() }

        service.handleSystemEvent(.sessionResigned)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.pauseCount, 1)

        service.handleSystemEvent(.sessionBecameActive)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.resumeCount, 1)
        XCTAssertEqual(resumedSessionID, "session-1")
    }

    private func settleSmartPauseTasks() async {
        for _ in 0..<4 {
            await Task.yield()
        }
    }
}

@MainActor
private final class SmartPauseTimerController: SmartPauseTimerControlling {
    private let subject = PassthroughSubject<TimerSnapshot, Never>()
    var snapshot = TimerSnapshot()
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0

    var smartPauseSnapshot: TimerSnapshot { snapshot }
    var smartPauseSnapshots: AnyPublisher<TimerSnapshot, Never> {
        subject.eraseToAnyPublisher()
    }

    func pauseForSmartPause() async throws -> TimerSnapshot {
        pauseCount += 1
        snapshot.state = "paused"
        subject.send(snapshot)
        return snapshot
    }

    func resumeFromSmartPause() async throws -> TimerSnapshot {
        resumeCount += 1
        snapshot.state = "running"
        subject.send(snapshot)
        return snapshot
    }
}

private final class SmartPauseMonitor: SmartPauseSystemMonitoring {
    private(set) var isStarted = false

    func start(handler: @escaping @MainActor (SmartPauseSystemEvent) -> Void) {
        isStarted = true
    }

    func stop() {
        isStarted = false
    }
}

private struct SmartPauseIdleProvider: SmartPauseIdleTimeProviding {
    let seconds: TimeInterval
    var idleSeconds: TimeInterval { seconds }
}

private final class SmartPauseMutableIdleProvider: SmartPauseIdleTimeProviding {
    var seconds: TimeInterval
    var idleSeconds: TimeInterval { seconds }

    init(seconds: TimeInterval) {
        self.seconds = seconds
    }
}
