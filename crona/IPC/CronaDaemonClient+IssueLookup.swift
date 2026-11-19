import Foundation

extension CronaDaemonClient {
    func listIssues(streamID: Int64) async throws -> [CronaIssue] {
        try await request(method: "issue.list", params: AnyEncodable(IssueStreamQuery(streamId: streamID)))
    }
}

private struct IssueStreamQuery: Encodable {
    let streamId: Int64
}
