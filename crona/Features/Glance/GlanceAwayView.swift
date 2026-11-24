import SwiftUI

struct GlanceAwayView: View {
    @ObservedObject var settings: CoreSettingsService
    let isToday: Bool
    let canChangeMode: Bool
    let onDisable: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.semantic(.away))
                .accessibilityHidden(true)

            Text(isToday ? "Away Today" : "Recorded Away Day")
                .font(.title2.weight(.semibold))

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isToday && settings.settings.awayModeEnabled {
                Button(action: onDisable) {
                    Label("Turn Off Away Mode", systemImage: "sun.max")
                }
                .buttonStyle(GlanceButtonStyle(prominent: true))
                .disabled(!canChangeMode || settings.isSaving)
            }

            if isToday, let error = settings.lastErrorDescription {
                Text(error).font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        if !isToday { return "Crona recorded this day as away." }
        if settings.settings.awayModeEnabled { return "Take the day at your own pace." }
        return "You have a rest day on your schedule. Enjoy the time away."
    }
}
