import Foundation

enum GlobalShortcutAction: String, CaseIterable, Identifiable {
    case peek, show, createIssue, startFocus, pauseResume, endSession, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .peek: "Toggle Peek"
        case .show: "Show Crona"
        case .createIssue: "Create Issue"
        case .startFocus: "Start Focus Session"
        case .pauseResume: "Pause / Resume Session"
        case .endSession: "End Session"
        case .settings: "Open Settings"
        }
    }
}

