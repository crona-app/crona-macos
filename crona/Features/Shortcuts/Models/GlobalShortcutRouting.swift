import Foundation

extension CompanionAppState {
    @MainActor
    func performGlobalShortcut(_ action: GlobalShortcutAction) async {
        if action == .peek { peek.toggle(appState: self); return }
        if action == .settings { openSettings(); return }
        if action == .pauseResume {
            let presentation = TimerPresentation.from(timerService.snapshot)
            do {
                if presentation.canPause {
                    try await timerService.pauseTimer()
                    shortcutFeedback.show("Session paused")
                } else if presentation.canResume {
                    try await timerService.resumeTimer()
                    shortcutFeedback.show("Session resumed")
                } else {
                    shortcutFeedback.show("Pause / Resume requires an active stopwatch session.")
                }
            } catch { shortcutFeedback.show(error.localizedDescription) }
            return
        }
        statusBarService.showPopupFromShortcut()
        if action == .show { return }
        if action == .createIssue, issueCreator.isPresented, issueCreator.issueBeingEdited == nil {
            globalShortcuts.focusCreator()
            return
        }
        if action == .endSession, endSession.isSheetPresented { return }
        if isPopoverModalPresented || habitEditor.isPresented || isStartingFocus
            || (action != .startFocus && (selectedFocusIssue != nil || isAdhocStartSelected)) {
            shortcutFeedback.show("Finish or dismiss the current flow first.")
            return
        }
        guard daemonConnection.connectionState == .connected else {
            shortcutFeedback.show("Crona is disconnected. Reconnect before using this action.")
            return
        }
        switch action {
        case .createIssue:
            issueCreator.presentCreator()
            globalShortcuts.focusCreator()
        case .startFocus:
            setSelectedPopoverTab(.now)
            if hasActiveFocusSession {
                shortcutFeedback.show("A focus session is already active.")
            } else if todayIsAway {
                shortcutFeedback.show("Turn off Away Mode before starting focus.")
            } else if selectedFocusIssue == nil && !isAdhocStartSelected {
                beginAdhocStart()
            }
        case .endSession:
            guard TimerPresentation.from(timerService.snapshot).canEnd else {
                shortcutFeedback.show("No active session to end.")
                return
            }
            endTimer()
        default: break
        }
    }
}
