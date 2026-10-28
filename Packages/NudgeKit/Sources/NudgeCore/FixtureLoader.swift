import Foundation

/// Loads a JSON array of synthetic requests for the DEBUG `-NudgeFixture` mode. Ages are `secondsAgo` relative to
/// load time so fixtures never go stale; omit it for "request time unknown".
enum FixtureLoader {
    struct Entry: Decodable {
        let repo: String
        let number: Int
        let title: String
        let author: String
        var headRef: String?
        /// "direct" or "org/slug".
        var via: String?
        var otherTeams: [String]?
        var requestedBy: String?
        var secondsAgo: TimeInterval?
    }

    static func load(_ url: URL, now: Date = Date()) throws -> [WaitingPR] {
        try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url)).map { waitingPR($0, now: now) }
    }

    static func waitingPR(_ e: Entry, now: Date) -> WaitingPR {
        let since = e.secondsAgo.map { now.addingTimeInterval(-$0) }
        let id = "PR_fixture_\(e.repo.replacingOccurrences(of: "/", with: "_"))_\(e.number)"
        let via = target(e.via)
        return WaitingPR(
            prID: id, repo: e.repo, number: e.number, title: e.title,
            url: URL(string: "https://github.com/\(e.repo)/pull/\(e.number)")!, author: e.author,
            headRef: e.headRef ?? "main", via: via, otherTeams: (e.otherTeams ?? []).map(target),
            requestedBy: e.requestedBy, requestKey: since == nil ? "\(id)#\(e.via ?? "direct")#unknown" : "RRE_\(id)",
            requestedAt: since, waitingSince: since)
    }

    private static func target(_ text: String?) -> RequestTarget {
        let parts = (text ?? "direct").split(separator: "/").map(String.init)
        return parts.count == 2 ? .team(org: parts[0], slug: parts[1]) : .direct
    }
}
