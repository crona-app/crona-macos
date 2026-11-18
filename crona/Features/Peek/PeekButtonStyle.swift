import SwiftUI

/// Capsule action button matching the popover's glass controls; `prominent` is the single primary action.
struct PeekButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let reduceMotion = SystemGlassSettings.shared.reduceMotion
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : PopupVisualTheme.primaryText)
            .padding(.horizontal, 14).frame(height: 32)
            .background {
                if prominent { Capsule().fill(Color.accentColor) } else { glassCapsuleBackground(emphasis: 0.08) }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
