import SwiftUI

/// Issue-details sections for the delay penalty and carry-over, shown only when they apply.
struct IssueRiskAndCarrySections: View {
    let appState: CompanionAppState
    let issue: DailyFocusIssue

    var body: some View {
        let riskLines = CronaPenaltyPresentation.detailLines(for: issue.penalty)
        if !riskLines.isEmpty {
            DetailSection(title: "Risk", icon: CronaPenaltyPresentation.markerIcon) {
                ForEach(riskLines, id: \.self) { line in
                    DetailStatusRow(title: line, tint: CronaPenaltyPresentation.colorKey.color)
                }
            }
        }

        let carryLines = CronaCarryPresentation.detailLines(for: issue) {
            formattedPopoverDate($0, appState: appState)
        }
        if !carryLines.isEmpty {
            DetailSection(title: "Carry", icon: CronaCarryPresentation.carriedIcon) {
                ForEach(carryLines, id: \.text) { line in
                    DetailStatusRow(
                        title: line.text,
                        tint: line.stalled
                            ? CronaPenaltyPresentation.colorKey.color : CronaCarryPresentation.carriedColor
                    )
                }
            }
        }
    }
}
