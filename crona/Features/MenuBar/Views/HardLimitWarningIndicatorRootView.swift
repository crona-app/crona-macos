import SwiftUI

struct HardLimitWarningIndicatorRootView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var popups: PopupCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let model = popups.hardLimitWarningIndicatorModel {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let snapshot = appState.timerService.snapshot
                let remaining = model.kind == .breakDeferred
                    ? snapshot.breakDeferral?.remainingSeconds(for: snapshot, at: timeline.date)
                    : TimerPresentation.projectedDisplaySeconds(for: snapshot, at: timeline.date)
                ZStack {
                    PopoverGlassBackground(cornerRadius: 20)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(nsColor: model.kind.tint))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Image(systemName: model.kind.symbolName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(PopupVisualTheme.primaryText)
                            }

                        Text(model.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PopupVisualTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let remaining {
                            let time = model.kind == .breakDeferred
                                ? MenuBarTextFormatter.formatClock(seconds: remaining)
                                : String(format: "%02d", remaining)
                            Text(time)
                                .font(.system(size: model.kind == .breakDeferred ? 16 : 18, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: remaining)
                                .foregroundStyle(PopupVisualTheme.primaryText)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                }
                .frame(width: 184)
                .clipShape(shape)
                .opacity(popups.isHardLimitWarningIndicatorAnimatingIn ? 1 : 0.02)
                .blur(radius: reduceMotion || popups.isHardLimitWarningIndicatorAnimatingIn ? 0 : 16)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: popups.isHardLimitWarningIndicatorAnimatingIn)
                .companionAppearance(appState)
            }
        }
    }
}
