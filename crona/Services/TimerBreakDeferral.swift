import Foundation

struct TimerBreakDeferral: Equatable {
    static let title = "Break deferred"
    static let symbolName = "clock.arrow.circlepath"

    let confirmedAt: Date
    var additionalSeconds: Int?

    func showsConfirmation(at now: Date) -> Bool {
        now < confirmedAt.addingTimeInterval(4)
    }

    func deadline(for snapshot: TimerSnapshot) -> Date? {
        guard let additionalSeconds, let start = snapshot.segmentStartTime else { return nil }
        return start.addingTimeInterval(Double(snapshot.hardLimitWorkSeconds + additionalSeconds))
    }

    func remaining(for snapshot: TimerSnapshot, at now: Date) -> TimeInterval? {
        if let deadline = deadline(for: snapshot) {
            return max(0, deadline.timeIntervalSince(now))
        }
        guard let additionalSeconds else { return nil }
        let elapsed = Double(snapshot.elapsedSeconds - snapshot.segmentElapsedOffsetSeconds)
            + max(0, now.timeIntervalSince(snapshot.snapshotAppliedAt))
        return max(0, Double(snapshot.hardLimitWorkSeconds + additionalSeconds) - elapsed)
    }

    func remainingSeconds(for snapshot: TimerSnapshot, at now: Date) -> Int? {
        remaining(for: snapshot, at: now).map { Int(ceil($0)) }
    }

    func duration(for snapshot: TimerSnapshot) -> TimeInterval? {
        guard let additionalSeconds, let initial = remaining(for: snapshot, at: confirmedAt) else { return nil }
        return max(Double(additionalSeconds), initial)
    }
}

struct TimerBreakDeferralTracker {
    private var previousSnapshot: TimerSnapshot?
    private var current: TimerBreakDeferral?
    private var recentIncrease: (seconds: Int, appliedAt: Date)?

    mutating func confirm(sessionID: String?, snapshot: TimerSnapshot, at now: Date) -> TimerBreakDeferral? {
        guard snapshot.canDeferBreak, sessionID == snapshot.sessionID, current == nil else { return nil }
        // A timer refresh can see the new total before the confirmation event arrives.
        let seconds = recentIncrease.flatMap { increase in
            now.timeIntervalSince(increase.appliedAt) < 5 ? increase.seconds : nil
        }
        let confirmed = TimerBreakDeferral(confirmedAt: now, additionalSeconds: seconds)
        current = confirmed
        return confirmed
    }

    mutating func reconcile(next: TimerSnapshot) -> TimerBreakDeferral? {
        let previous = previousSnapshot
        previousSnapshot = next
        guard let previous, next.canDeferBreak, previous.canDeferBreak,
              previous.sessionID == next.sessionID,
              previous.segmentStartTime == next.segmentStartTime else {
            current = nil
            recentIncrease = nil
            return nil
        }

        let increase = next.hardLimitTotalSeconds - previous.hardLimitTotalSeconds
        if increase != 0 {
            // The daemon adds exactly the deferral to the session total.
            if [30, 60, 120].contains(increase) {
                recentIncrease = (increase, next.snapshotAppliedAt)
                if current?.additionalSeconds == nil {
                    current?.additionalSeconds = increase
                }
            } else {
                recentIncrease = nil
            }
        }
        return current
    }

    mutating func clearRecentIncrease() {
        recentIncrease = nil
    }
}

private extension TimerSnapshot {
    var canDeferBreak: Bool {
        sessionID != nil && state == "running" && segmentType == "work"
            && hardLimitActive && hardLimitKind == .pomodoro && !hardLimitExpired
            && hardLimitWorkSeconds > 0
    }
}
