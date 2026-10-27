import Foundation

private struct CronaTagFiltersSettings: Decodable {
    let tagFilters: [String: String]?
}

extension CronaDaemonClient {
    func listTags() async throws -> [CronaTag] {
        try await request(method: "tag.list")
    }

    func setIssueTags(issueID: Int64, tags: [String]) async throws -> CronaIssue {
        try await request(
            method: "issue.tags.set", params: AnyEncodable(CronaSetTagsRequest(id: issueID, tags: tags)))
    }

    func setHabitTags(habitID: Int64, tags: [String]) async throws -> JSONValue {
        try await request(
            method: "habit.tags.set", params: AnyEncodable(CronaSetTagsRequest(id: habitID, tags: tags)))
    }

    func tagFiltersGet() async throws -> [String: String] {
        let all: [String: CronaTagFiltersSettings] = try await request(method: "settings.get_all")
        return (all["local"] ?? all.values.first)?.tagFilters ?? [:]
    }

    func tagFiltersPatch(_ filters: [String: String]) async throws {
        let _: JSONValue = try await request(
            method: "settings.patch",
            params: AnyEncodable([
                "key": JSONValue.string("tagFilters"),
                "value": JSONValue.object(filters.mapValues { JSONValue.string($0) }),
            ])
        )
    }

    func dashboardDistribution(start: String, end: String, groupBy: String) async throws
        -> CronaTimeDistributionSummary
    {
        try await request(
            method: "dashboard.distribution",
            params: AnyEncodable(
                CronaDashboardSummaryQuery(
                    start: start, end: end, groupBy: groupBy, repoID: nil, streamID: nil, issueID: nil)))
    }
}
