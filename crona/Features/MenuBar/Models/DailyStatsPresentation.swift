import Foundation

struct DailyStatsPresentation {
    let score: CronaFocusScoreSummary
    let metrics: CronaDailyMetricsDay

    var workedFraction: Double {
        guard score.targetWorkedSeconds > 0 else { return 0 }
        return Double(max(0, metrics.workedSeconds)) / Double(score.targetWorkedSeconds)
    }
    var focusFraction: Double? {
        let work = max(0, metrics.workedSeconds)
        let rest = max(0, metrics.restSeconds)
        guard work + rest > 0 else { return nil }
        return Double(work) / Double(work + rest)
    }
    var remainingSeconds: Int { max(0, score.targetWorkedSeconds - max(0, metrics.workedSeconds)) }
    var averageSessionSeconds: Int? {
        guard metrics.sessionCount > 0 else { return nil }
        return max(0, metrics.workedSeconds) / metrics.sessionCount
    }
    var issuesFraction: Double {
        guard metrics.totalIssues > 0 else { return 0 }
        return Double(max(0, metrics.completedIssues)) / Double(metrics.totalIssues)
    }
    var habitsFraction: Double {
        guard metrics.habitDueCount > 0 else { return 0 }
        return Double(max(0, metrics.habitCompletedCount)) / Double(metrics.habitDueCount)
    }
}
