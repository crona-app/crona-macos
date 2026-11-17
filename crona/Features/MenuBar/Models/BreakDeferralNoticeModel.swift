import Foundation

/// Keeps a confirmed deferral visible briefly, then silences the old boundary warning.
@MainActor
final class BreakDeferralNoticeModel {
    private var sessionID: String?
    private var segmentStart: Date?
    private var visibleUntil: Date?

    func record(sessionID: String?, snapshot: TimerSnapshot, now: Date = Date()) {
        guard let sessionID, snapshot.sessionID == sessionID,
              snapshot.state == "running", snapshot.segmentType == "work" else { return }
        self.sessionID = sessionID
        segmentStart = snapshot.segmentStartTime
        visibleUntil = now.addingTimeInterval(4)
    }

    func suppressesWarning(for snapshot: TimerSnapshot) -> Bool {
        guard sessionID != nil else { return false }
        guard snapshot.sessionID == sessionID, snapshot.segmentType == "work",
              snapshot.segmentStartTime == segmentStart else {
            sessionID = nil
            visibleUntil = nil
            return false
        }
        return true
    }

    func indicator(for snapshot: TimerSnapshot, now: Date = Date()) -> HardLimitWarningIndicatorModel? {
        guard suppressesWarning(for: snapshot), let visibleUntil, now < visibleUntil else { return nil }
        return HardLimitWarningIndicatorModel(id: "\(sessionID ?? ""):breakDeferred",
            kind: .breakDeferred, title: "Break deferred", remainingText: "")
    }
}
