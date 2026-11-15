import SwiftUI

/// Retains the source view while details are shown, including its scroll position and drafts.
struct PopoverDailyContentView: View {
    @ObservedObject var appState: CompanionAppState
    let displayClock: PopupDisplayClock

    var body: some View {
        ZStack(alignment: .top) {
            source
                .opacity(appState.popoverDetailsRoute == nil ? 1 : 0)
                .allowsHitTesting(appState.popoverDetailsRoute == nil)
                .accessibilityHidden(appState.popoverDetailsRoute != nil)
            if let route = appState.popoverDetailsRoute {
                PopoverDetailView(appState: appState, route: route)
            }
        }
    }

    @ViewBuilder private var source: some View {
        if appState.hasActiveFocusSession {
            IssuesTabView(appState: appState, displayClock: displayClock)
        } else if appState.todayIsAway {
            AwayModeView(appState: appState)
        } else {
            switch appState.selectedPopoverTab {
            case .now: IssuesTabView(appState: appState, displayClock: displayClock)
            case .habits: HabitsTabView(appState: appState)
            case .wellbeing: WellbeingTabView(appState: appState)
            case .stats: StatsTabView(appState: appState)
            }
        }
    }
}
