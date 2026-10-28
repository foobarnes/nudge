import Foundation

/// Turns search results into the requests currently waiting on the viewer. `review-requested:@me` also matches
/// team requests, so the target is always re-derived from `reviewRequests`.
enum ReviewRequestResolver {
    /// `teams` holds `.team` targets the viewer belongs to.
    static func resolve(nodes: [PRNode], viewer: String, teams: Set<RequestTarget>) -> [WaitingPR] {
        let myTeams = Set(teams.map(identity))
        return nodes.compactMap { resolve($0, viewer: viewer.lowercased(), teams: myTeams) }
    }

    private static func identity(_ target: RequestTarget) -> String {
        switch target {
        case .direct: "direct"
        case let .team(org, slug): "\(org)/\(slug)".lowercased()
        }
    }

    private static func target(_ reviewer: Reviewer?, viewer: String, teams: Set<String>) -> RequestTarget? {
        switch reviewer {
        case let .user(login) where login.lowercased() == viewer: .direct
        case let .team(org, slug) where teams.contains("\(org)/\(slug)".lowercased()): .team(org: org, slug: slug)
        default: nil
        }
    }

    private struct Event {
        let id: String
        let createdAt: Date
        let actor: String?
    }

    private static func resolve(_ node: PRNode, viewer: String, teams: Set<String>) -> WaitingPR? {
        // A person's draft isn't ready for review yet; a bot's draft (an automated fix) is waiting as soon as it asks.
        guard !node.isDraft || node.author?.isBot == true else { return nil }
        var targets: [RequestTarget] = []
        for request in node.reviewRequests.nodes {
            if let t = target(request?.requestedReviewer, viewer: viewer, teams: teams), !targets.contains(t) {
                targets.append(t)
            }
        }
        guard !targets.isEmpty else { return nil }

        var latest: [String: Event] = [:]
        var readyAt: Date?
        for item in node.timelineItems.nodes {
            switch item {
            case let .requested(id, createdAt, actor, reviewer):
                guard let t = target(reviewer, viewer: viewer, teams: teams) else { continue }
                if latest[identity(t)].map({ createdAt >= $0.createdAt }) ?? true {
                    latest[identity(t)] = Event(id: id, createdAt: createdAt, actor: actor)
                }
            case let .ready(createdAt):
                readyAt = max(readyAt ?? createdAt, createdAt)
            case .other, nil:
                continue
            }
        }

        let teamTargets = targets.filter(\.isTeam)
        let via = targets.contains(.direct) ? .direct : teamTargets.max { a, b in
            (latest[identity(a)]?.createdAt ?? .distantPast) < (latest[identity(b)]?.createdAt ?? .distantPast)
        }!
        let event = latest[identity(via)]
        let waitingSince = event.map { e in readyAt.map { max($0, e.createdAt) } ?? e.createdAt }
        return WaitingPR(
            prID: node.id, repo: node.repository.nameWithOwner, number: node.number, title: node.title, url: node.url,
            author: node.author?.login ?? "ghost", headRef: node.headRefName, via: via,
            otherTeams: teamTargets.filter { $0 != via }, requestedBy: event?.actor,
            requestKey: event?.id ?? "\(node.id)#\(identity(via))#unknown",
            requestedAt: event?.createdAt, waitingSince: waitingSince)
    }
}
