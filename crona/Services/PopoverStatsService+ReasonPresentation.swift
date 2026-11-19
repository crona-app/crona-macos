import Foundation

extension PopoverStatsService {
    static func title(for reason: String) -> String {
        switch reason {
        case "no_activity": return "Ready to begin"
        case "under_target": return "Build momentum"
        case "needs_breaks": return "Take a break"
        case "overextended": return "Overextended"
        default: return "Steady rhythm"
        }
    }

    static func message(for reason: String) -> String {
        switch reason {
        case "no_activity":
            return "Start a focused session to build today’s score."
        case "under_target":
            return "You’re below today’s planned focus time."
        case "needs_breaks":
            return "Your focus time is outpacing your recovery time."
        case "overextended":
            return "You’ve pushed beyond your target without enough recovery."
        default:
            return "Your work and recovery are in a healthy balance."
        }
    }

}
