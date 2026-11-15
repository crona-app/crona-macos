import SwiftUI

/// A recorded away day replaces daily content while keeping date and Library navigation.
struct HistoricalAwayDayView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var day: PopoverDayModel
    @ObservedObject private var settings: CoreSettingsService

    init(appState: CompanionAppState) {
        self.appState = appState
        day = appState.day
        settings = appState.coreSettingsService
    }

    private var libraryDestination: LibraryDestination? {
        switch appState.selectedPopoverTab {
        case .wellbeing: return .checkIns
        case .stats: return .review
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            PopoverDayHeader(appState: appState, libraryDestination: libraryDestination)
            VStack(spacing: 12) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(PopupVisualTheme.semantic(.success))
                Text("Away day").font(.title3.bold())
                Text(CronaDateDisplayFormatter.string(fromISODate: day.selectedDate, settings: settings.settings))
                    .font(.caption).foregroundStyle(.secondary)
                Text("You chose to rest and recover.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .padding(.horizontal, 16)
            .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 20))
            .accessibilityElement(children: .combine)
        }
    }
}
