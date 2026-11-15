import Foundation

struct CronaPlanWindow: Decodable, Equatable {
    let startDate: String
    let endDate: String
    let plannedCount: Int
    let completedCount: Int
    let failedCount: Int
    let abandonedCount: Int
    let missedCount: Int
    let carryOverCount: Int
    let days: [Day]?

    struct Day: Decodable, Equatable {
        let date: String
        let plannedCount: Int
        let completedCount: Int
    }

    var completionRate: Double? {
        plannedCount > 0 ? Double(completedCount) / Double(plannedCount) : nil
    }
    var fullyCompletedDays: Int {
        (days ?? []).filter { $0.plannedCount > 0 && $0.completedCount == $0.plannedCount }.count
    }
    var plannedDays: Int { (days ?? []).filter { $0.plannedCount > 0 }.count }
}

struct CronaEstimateSummary: Decodable, Equatable {
    let totalEstimateMinutes: Int
    let totalActualSeconds: Int
    let estimatedItems: Int
    let averageDeltaMinutes: Double
    let averageDeltaPercent: Double
    let estimateBias: String

    var deltaSeconds: Int { totalActualSeconds - totalEstimateMinutes * 60 }
    var biasDescription: String {
        switch estimateBias {
        case "under": return "estimates tend to be low"
        case "over": return "estimates tend to be high"
        case "balanced": return "estimates are balanced"
        default: return "estimate accuracy unavailable"
        }
    }
}

struct CronaIssueOperation: Decodable, Equatable, Identifiable {
    let id: String
    let entity: String
    let entityID: String
    let action: String
    let payload: [String: JSONValue]?
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case id, entity, action, payload, timestamp
        case entityID = "entityId"
    }

    var actionLabel: String {
        switch action {
        case "create": return "Added"
        case "delete": return "Deleted"
        case "restore": return "Restored"
        default: break
        }
        if let to = payload?["to"]?.stringValue, !to.isEmpty {
            if let from = payload?["from"]?.stringValue, !from.isEmpty {
                return "\(Self.statusTitle(from)) → \(Self.statusTitle(to))"
            }
            return "Status → \(Self.statusTitle(to))"
        }
        if let date = payload?["todoForDate"] {
            return date.stringValue.flatMap { $0.isEmpty ? nil : "Scheduled \($0)" } ?? "Unscheduled"
        }
        if let status = payload?["status"]?.stringValue { return "Status → \(Self.statusTitle(status))" }
        return "Updated"
    }
    private static func statusTitle(_ status: String) -> String {
        CronaIssueStatus(rawValue: status)?.title ?? status.replacingOccurrences(of: "_", with: " ").capitalized
    }

}

extension CronaDaemonClient {
    func checkInRange(start: String = "0001-01-01", end: String = "9999-12-31") async throws -> [CronaDailyCheckIn] {
        try await request(method: "checkin.range", params: AnyEncodable(CronaDateRangeQuery(start: start, end: end)))
    }

    func checkInDelete(date: String) async throws -> CronaOKResponse {
        try await request(method: "checkin.delete", params: AnyEncodable(CronaDailyCheckInQuery(date: date)))
    }

    func habitHistory() async throws -> [CronaHabitCompletion] {
        try await request(method: "habit.history")
    }

    func operations(since: String) async throws -> [CronaIssueOperation] {
        struct Query: Encodable { let since: String }
        return try await request(method: "ops.since", params: AnyEncodable(Query(since: since)))
    }

    func planWindow(start: String, end: String) async throws -> CronaPlanWindow {
        try await request(method: "dashboard.window", params: AnyEncodable(CronaDateRangeQuery(start: start, end: end)))
    }

    func estimateSummary(start: String, end: String) async throws -> CronaEstimateSummary {
        try await request(
            method: "dashboard.goal_progress",
            params: AnyEncodable(
                CronaDashboardSummaryQuery(
                    start: start, end: end, groupBy: "issue", repoID: nil, streamID: nil, issueID: nil)))
    }
}
