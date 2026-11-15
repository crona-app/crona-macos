import SwiftUI

struct IssueProgressSummaryView: View {
    let issue: DailyFocusIssue
    private var estimateSeconds: Int? {
        guard let minutes = issue.estimateMinutes, minutes > 0 else { return nil }
        return minutes * 60
    }
    private var workedSeconds: Int { max(0, issue.workedSeconds) }
    private var tint: Color {
        if let estimateSeconds, workedSeconds > estimateSeconds { return PopupVisualTheme.semantic(.warning) }
        return PopupVisualTheme.semantic(.focus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                CronaIssueStatusPresentation.status(for: issue.status)?.title ?? issue.status.capitalized,
                systemImage: CronaIssueStatusPresentation.icon(for: issue.status)
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(CronaIssueStatusPresentation.color(for: issue.status))

            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.15), lineWidth: 6)
                    if let estimateSeconds {
                        let fraction = Double(workedSeconds) / Double(estimateSeconds)
                        Circle().trim(from: 0, to: min(1, fraction))
                            .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                                .font(.headline.monospacedDigit())
                            Text("Time used").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "clock").font(.title2).foregroundStyle(tint)
                    }
                }
                .padding(3)
                .frame(width: 86, height: 86)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(duration(workedSeconds)).font(.title2.bold().monospacedDigit())
                    if let estimateSeconds {
                        Text("worked · \(duration(estimateSeconds)) estimate")
                            .font(.caption).foregroundStyle(.secondary)
                        let remaining = estimateSeconds - workedSeconds
                        Label(
                            remaining == 0
                                ? "Estimate reached"
                                : "\(duration(abs(remaining))) \(remaining > 0 ? "remaining" : "over estimate")",
                            systemImage: remaining >= 0 ? "clock" : "exclamationmark.circle"
                        )
                        .font(.caption.weight(.medium)).foregroundStyle(tint)
                    } else {
                        Text("worked").font(.caption).foregroundStyle(.secondary)
                        Text("No estimate set").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Tracked time measures effort, not completion.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 16))
    }

    private func duration(_ seconds: Int) -> String {
        MenuBarTextFormatter.formatCompactDuration(seconds: seconds)
    }
}
