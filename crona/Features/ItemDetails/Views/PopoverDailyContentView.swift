import SwiftUI

/// Retains the source view while details are shown, including its scroll position and drafts.
struct PopoverDailyContentView: View {
    @ObservedObject var appState: CompanionAppState
    let displayClock: PopupDisplayClock
    @ObservedObject private var day: PopoverDayModel
    @ObservedObject private var settings: CoreSettingsService

    init(appState: CompanionAppState, displayClock: PopupDisplayClock) {
        self.appState = appState
        self.displayClock = displayClock
        day = appState.day
        settings = appState.coreSettingsService
    }

    private var isHistoricalAway: Bool { day.isRecordedAway(in: settings.settings) }

    var body: some View {
        ZStack(alignment: .top) {
            source
                .opacity(appState.popoverDetailsRoute == nil || isHistoricalAway ? 1 : 0)
                .allowsHitTesting(appState.popoverDetailsRoute == nil || isHistoricalAway)
                .accessibilityHidden(appState.popoverDetailsRoute != nil && !isHistoricalAway)
            if let route = appState.popoverDetailsRoute, !isHistoricalAway {
                PopoverDetailView(appState: appState, route: route)
            }
        }
        .onChange(of: isHistoricalAway) { _, isAway in
            if isAway { appState.dismissDetails() }
        }
    }

    @ViewBuilder private var source: some View {
        if appState.hasActiveFocusSession {
            IssuesTabView(appState: appState, displayClock: displayClock)
        } else if appState.todayIsAway {
            AwayModeView(appState: appState)
        } else if isHistoricalAway {
            HistoricalAwayDayView(appState: appState)
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
