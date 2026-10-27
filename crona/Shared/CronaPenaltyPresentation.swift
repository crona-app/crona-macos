import SwiftUI

enum CronaPenaltyPresentation {
    static let colorKey: CronaIssueStatusColor = .red
    static let markerIcon = "exclamationmark.triangle.fill"

    static func showsMarker(_ penalty: DailyFocusPenalty?) -> Bool {
        penalty?.highRisk == true
    }

    static func detailLines(for penalty: DailyFocusPenalty?) -> [String] {
        guard let penalty else { return [] }
        if penalty.highRisk {
            let unit = penalty.delayedDays == 1 ? "day" : "days"
            return ["High risk · delayed \(penalty.delayedDays) \(unit)"]
        }
        if penalty.becomesHighRiskIfPostponed {
            return ["Postponing 1 day makes this high risk"]
        }
        return []
    }

    // Plan penalties are only known for the daily focus date, so other days show no count.
    static func statsHighRiskCount(statsDate: String, focus: DailyFocusSnapshot) -> Int? {
        guard statsDate == focus.date, focus.highRiskCount > 0 else { return nil }
        return focus.highRiskCount
    }
}

struct PenaltyRiskMarker: View {
    let penalty: DailyFocusPenalty?

    var body: some View {
        if CronaPenaltyPresentation.showsMarker(penalty) {
            HStack(spacing: 4) {
                Image(systemName: CronaPenaltyPresentation.markerIcon)
                Text("High risk")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(CronaPenaltyPresentation.colorKey.color)
            .hoverInfo {
                HoverInfoLines(lines: CronaPenaltyPresentation.detailLines(for: penalty).map { ($0, nil) })
            }
        }
    }
}
