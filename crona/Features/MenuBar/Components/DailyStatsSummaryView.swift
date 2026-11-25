import SwiftUI

/// The day's score, effort and outcomes share one compact summary, like the TUI's vitals.
struct DailyStatsSummaryView: View {
    let score: CronaFocusScoreSummary
    let metrics: CronaDailyMetricsDay
    let message: String
    let highRiskCount: Int?
    var embedded = false

    private var stats: DailyStatsPresentation { DailyStatsPresentation(score: score, metrics: metrics) }
    private var scoreTint: Color {
        if score.reason == "no_activity" { return .secondary }
        switch score.level {
        case "strong": return PopupVisualTheme.semantic(.success)
        case "steady": return PopupVisualTheme.semantic(.focus)
        case "low": return PopupVisualTheme.semantic(.error)
        default: return PopupVisualTheme.semantic(.warning)
        }
    }
    private var scoreLevel: String {
        score.reason == "no_activity" ? "No activity" : score.level.replacingOccurrences(of: "_", with: " ").capitalized
    }
    private var issueNote: String {
        if let highRiskCount, highRiskCount > 0 { return "\(highRiskCount) high risk" }
        if metrics.abandonedIssues > 0 { return "\(metrics.abandonedIssues) abandoned" }
        return metrics.totalIssues > 0
            ? "\(max(0, metrics.totalIssues - metrics.completedIssues)) left" : "None planned"
    }
    private var habitNote: String {
        if metrics.habitFailedCount > 0 { return "\(metrics.habitFailedCount) failed" }
        return metrics.habitDueCount > 0
            ? "\(max(0, metrics.habitDueCount - metrics.habitCompletedCount)) left" : "None due"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                gauge(
                    "Score", value: String(score.score), fraction: Double(score.score) / 100,
                    tint: scoreTint, detail: scoreLevel,
                    secondary: stats.focusFraction.map {
                        "\($0.formatted(.percent.precision(.fractionLength(0)))) focus"
                    } ?? "— focus"
                )
                .help(
                    "Focus score: \(score.score)/100. Focus percentage is worked time divided by worked plus break time."
                )
                gauge(
                    "Worked", value: duration(metrics.workedSeconds), fraction: stats.workedFraction,
                    tint: stats.workedFraction >= 1
                        ? PopupVisualTheme.semantic(.success) : PopupVisualTheme.semantic(.focus),
                    detail: score.targetWorkedSeconds > 0 ? "of \(duration(score.targetWorkedSeconds))" : "No target",
                    secondary: score.targetWorkedSeconds > 0
                        ? (stats.remainingSeconds > 0 ? "\(duration(stats.remainingSeconds)) to go" : "Target met") : ""
                )
                gauge(
                    "Issues", value: "\(metrics.completedIssues)/\(metrics.totalIssues)",
                    fraction: stats.issuesFraction,
                    tint: PopupVisualTheme.semantic(.success), detail: issueNote,
                    secondary: highRiskCount.map {
                        $0 > 0 && metrics.abandonedIssues > 0 ? "\(metrics.abandonedIssues) abandoned" : ""
                    } ?? "")
                gauge(
                    "Habits", value: "\(metrics.habitCompletedCount)/\(metrics.habitDueCount)",
                    fraction: stats.habitsFraction,
                    tint: PopupVisualTheme.semantic(.info), detail: habitNote, secondary: "")
            }
            Divider().overlay(PopupVisualTheme.divider.opacity(0.5))
            HStack(spacing: 0) {
                fact("Sessions", value: String(metrics.sessionCount), icon: "rectangle.stack")
                fact("Average", value: stats.averageSessionSeconds.map(duration) ?? "—", icon: "clock")
                fact("Breaks", value: duration(metrics.restSeconds), icon: "cup.and.saucer")
            }
            if !message.isEmpty {
                Text(message).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(embedded ? 0 : 14)
        .background {
            if !embedded { subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 20) }
        }
    }

    private func gauge(
        _ title: String, value: String, fraction: Double, tint: Color,
        detail: String, secondary: String
    ) -> some View {
        VStack(spacing: 5) {
            ZStack(alignment: .top) {
                Circle().trim(from: 0.5, to: 1)
                    .stroke(.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 64, height: 64).padding(3)
                Circle().trim(from: 0.5, to: 0.5 + min(1, max(0, fraction)) / 2)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 64, height: 64).padding(3)
                Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 66, height: 42, alignment: .bottom)
            }
            .frame(width: 70, height: 42, alignment: .top).clipped()
            Text(title).font(.caption.weight(.semibold))
            VStack(spacing: 3) {
                Text(detail).foregroundStyle(tint)
                Text(secondary.isEmpty ? " " : secondary).foregroundStyle(.secondary)
            }
            .font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail, secondary].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private func fact(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity)
    }
    private func duration(_ seconds: Int) -> String {
        MenuBarTextFormatter.formatCompactDuration(seconds: max(0, seconds))
    }
}
