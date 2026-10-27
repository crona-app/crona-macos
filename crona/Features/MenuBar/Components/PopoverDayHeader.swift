import SwiftUI

/// Previous/next day pill shared by the day-based popover tabs. Moving it moves every tab.
struct PopoverDayHeader: View {
    let appState: CompanionAppState
    @ObservedObject private var day: PopoverDayModel

    init(appState: CompanionAppState) {
        self.appState = appState
        self._day = ObservedObject(wrappedValue: appState.day)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Button {
                    day.showPreviousDay()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous day")

                Text(title(for: day.selectedDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText)
                    .lineLimit(1)

                Button {
                    day.showNextDay()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!day.canShowNextDay)
                .accessibilityLabel("Next day")
            }
            .frame(height: 22)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .modifier(PopoverDatePillSurfaceModifier())
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if !day.isToday {
                Button {
                    day.showToday()
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.78))
                .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.08)))
                .help("Return to today")
                .accessibilityLabel("Return to today")
                .padding(.trailing, 6)
            }
        }
    }

    private func title(for date: String) -> String {
        let today =
            appState.daemonConnection.currentDate.isEmpty
            ? DailyFocusService.todayString()
            : appState.daemonConnection.currentDate
        let resolvedDate = date.isEmpty ? today : date
        if resolvedDate == today {
            return "Today"
        } else if resolvedDate == CronaCalendarDate.adding(days: -1, to: today) {
            return "Yesterday"
        }
        return formattedPopoverDate(resolvedDate, appState: appState)
    }
}

struct PopoverDatePillSurfaceModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if SystemGlassSettings.shared.reduceTransparency {
            content.background(Capsule().fill(PopupVisualTheme.controlBackground))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(Capsule().fill(.regularMaterial))
                .overlay {
                    Capsule()
                        .strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 0.7)
                }
        }
    }
}
