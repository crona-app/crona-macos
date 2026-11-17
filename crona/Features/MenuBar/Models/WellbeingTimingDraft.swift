import Foundation

struct WellbeingTimingDraft: Equatable {
    var hasSleepDuration = false
    var sleepDuration = "8h0m"
    var hasSleepScore = false
    var sleepScoreText = "80"
    var hasScreenTime = false
    var screenDuration = "2h0m"

    init(entry: CronaDailyCheckIn? = nil) {
        if let hours = entry?.sleepHours {
            hasSleepDuration = true
            sleepDuration = MenuBarTextFormatter.formatMinutes(Int((hours * 60).rounded()))
        }
        if let score = entry?.sleepScore {
            hasSleepScore = true
            sleepScoreText = String(score)
        }
        if let minutes = entry?.screenTimeMinutes {
            hasScreenTime = true
            screenDuration = MenuBarTextFormatter.formatMinutes(minutes)
        }
    }

    var sleepHours: Double? {
        guard hasSleepDuration,
              let minutes = DurationInput.minutes(sleepDuration, maximum: 1_440) else { return nil }
        return Double(minutes) / 60
    }

    var screenTimeMinutes: Int? {
        hasScreenTime ? DurationInput.minutes(screenDuration, maximum: 1_440) : nil
    }

    var sleepScore: Int? {
        guard hasSleepScore,
              let value = Int(sleepScoreText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...100).contains(value) else { return nil }
        return value
    }

    var validationError: String? {
        if hasSleepDuration && sleepHours == nil {
            return "Enter sleep duration between 0m and 24h0m, such as 7h18m."
        }
        if hasSleepScore && sleepScore == nil {
            return "Enter a sleep score from 0 to 100."
        }
        if hasScreenTime && screenTimeMinutes == nil {
            return "Enter screen time between 0m and 24h0m, such as 2h13m."
        }
        return nil
    }
}
