import SwiftUI

/// A ring that fills, then settles into a checkmark, to mark a finished focus block.
struct FocusCompleteRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var showsCheck = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(PopupVisualTheme.primaryText.opacity(0.1), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    PopupVisualTheme.semantic(.success),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PopupVisualTheme.semantic(.success))
                .scaleEffect(showsCheck ? 1 : 0.4)
                .opacity(showsCheck ? 1 : 0)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else {
                progress = 1
                showsCheck = true
                return
            }
            withAnimation(.easeOut(duration: 0.6)) { progress = 1 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.5)) { showsCheck = true }
        }
    }
}

enum HardLimitTodayLine {
    /// "3rd focus session today", counting the session that just hit its limit.
    static func text(completedSessionsToday: Int?) -> String? {
        guard let completed = completedSessionsToday, completed >= 0 else { return nil }
        let current = completed + 1
        guard current > 1 else { return "First focus session today" }
        return "\(ordinal(current)) focus session today"
    }

    static func ordinal(_ value: Int) -> String {
        let tens = value % 100
        let suffix: String
        if (11...13).contains(tens) {
            suffix = "th"
        } else {
            switch value % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(value)\(suffix)"
    }
}

extension HardLimitExtendChoice {
    var chipTitle: String {
        switch self {
        case .minutes1: return "+1 min"
        case .minutes5: return "+5 min"
        case .minutes15: return "+15 min"
        case .session1: return "+1 session"
        case .session2: return "+2 sessions"
        }
    }
}

struct HardLimitExtendChip: View {
    let choice: HardLimitExtendChoice
    let shortcut: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            VStack(spacing: 4) {
                Text(choice.chipTitle)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(PopupVisualTheme.primaryText)
                Text(shortcut)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.45))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(shape.fill(PopupVisualTheme.primaryText.opacity(isSelected ? 0.12 : 0.05)))
            .overlay(
                shape.strokeBorder(
                    isSelected ? PopupVisualTheme.semantic(.info) : PopupVisualTheme.border,
                    lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(shortcut)), modifiers: [])
        .accessibilityLabel(choice.chipTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The issue the session is for, so the hard-limit and end-session screens never lose that context.
struct FocusIssueContextCard: View {
    @ObservedObject private var timerService: TimerService
    @ObservedObject private var contextService: ContextService
    @ObservedObject private var dailyIssues: DailyIssuesModel

    init(appState: CompanionAppState) {
        self.timerService = appState.timerService
        self.contextService = appState.contextService
        self.dailyIssues = appState.dailyIssues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PopupVisualTheme.primaryText)
                .lineLimit(2)
            HStack(spacing: 10) {
                if let location {
                    Label(location, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if let progress {
                    Text(progress).monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PopupVisualTheme.primaryText.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(PopupVisualTheme.border, lineWidth: 1))
        )
    }

    private var isAdhoc: Bool { timerService.snapshot.adhoc }

    private var title: String {
        isAdhoc ? "Ad Hoc Focus" : (contextService.snapshot.issueTitle ?? "Focus session")
    }

    private var location: String? {
        guard !isAdhoc else { return nil }
        let parts = [contextService.snapshot.repoName, contextService.snapshot.streamName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " › ")
    }

    private var progress: String? {
        guard !isAdhoc, let issueID = timerService.snapshot.issueID,
            let issue = dailyIssues.allIssues.first(where: { $0.id == issueID })
        else { return nil }
        return Self.progressText(workedSeconds: issue.workedSeconds, estimateMinutes: issue.estimateMinutes)
    }

    static func progressText(workedSeconds: Int, estimateMinutes: Int?) -> String {
        let worked = MenuBarTextFormatter.formatCompactDuration(seconds: workedSeconds)
        guard let estimate = estimateMinutes, estimate > 0 else { return "\(worked) worked" }
        return "\(worked) of \(MenuBarTextFormatter.formatMinutes(estimate)) estimate"
    }
}
