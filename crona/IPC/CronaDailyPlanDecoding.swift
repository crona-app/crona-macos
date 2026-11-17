import Foundation

extension CronaDailyPlan {
    private enum PlanDecodingKeys: String, CodingKey {
        case id, date, createdAt, updatedAt, entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PlanDecodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(String.self, forKey: .date)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        // The daemon omits entries when a day's plan is empty.
        entries = try container.decodeIfPresent([CronaDailyPlanEntry].self, forKey: .entries) ?? []
    }
}
