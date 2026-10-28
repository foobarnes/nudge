import Foundation

// Decodable shapes of the GraphQL responses (see the spec's Examples and docs/spikes/phase0.md).

struct LoginNode: Decodable, Sendable { let login: String }

struct PageInfo: Decodable, Sendable {
    let hasNextPage: Bool
    let endCursor: String?
}

/// A requested reviewer. Anything that isn't a User or Team (Bot, Mannequin, EnterpriseTeam) is `.other`.
enum Reviewer: Decodable, Hashable, Sendable {
    case user(String)
    case team(org: String, slug: String)
    case other

    private enum Keys: String, CodingKey { case __typename, login, slug, organization }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .__typename)
        if type == "User", let login = try? c.decode(String.self, forKey: .login) {
            self = .user(login)
        } else if type == "Team", let slug = try? c.decode(String.self, forKey: .slug),
                  let org = try? c.decode(LoginNode.self, forKey: .organization) {
            self = .team(org: org.login, slug: slug)
        } else {
            self = .other
        }
    }
}

struct ReviewRequests: Decodable, Sendable {
    struct Node: Decodable, Sendable { let requestedReviewer: Reviewer? }
    var pageInfo: PageInfo
    var nodes: [Node?]
}

enum TimelineItem: Decodable, Sendable {
    case requested(id: String, createdAt: Date, actor: String?, reviewer: Reviewer?)
    case ready(createdAt: Date)
    case other

    private enum Keys: String, CodingKey { case __typename, id, createdAt, actor, requestedReviewer }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decodeIfPresent(String.self, forKey: .__typename) {
        case "ReviewRequestedEvent":
            self = .requested(id: try c.decode(String.self, forKey: .id),
                              createdAt: try c.decode(Date.self, forKey: .createdAt),
                              actor: try c.decodeIfPresent(LoginNode.self, forKey: .actor)?.login,
                              reviewer: try c.decodeIfPresent(Reviewer.self, forKey: .requestedReviewer))
        case "ReadyForReviewEvent":
            self = .ready(createdAt: try c.decode(Date.self, forKey: .createdAt))
        default:
            self = .other
        }
    }
}

struct PRNode: Decodable, Sendable {
    struct Repository: Decodable, Sendable { let nameWithOwner: String }
    struct Timeline: Decodable, Sendable { let nodes: [TimelineItem?] }

    let id: String
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let headRefName: String
    let author: LoginNode?
    let repository: Repository
    var reviewRequests: ReviewRequests
    let timelineItems: Timeline
}

/// One search result: a pull request, an issue (an empty object under `... on PullRequest`), or a node that
/// came back null or malformed, which makes the snapshot incomplete.
enum SearchNode: Decodable, Sendable {
    case pr(PRNode)
    case skipped
    case failed

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .failed; return }
        if let pr = try? single.decode(PRNode.self) { self = .pr(pr); return }
        let isEmpty = (try? decoder.container(keyedBy: AnyKey.self))?.allKeys.isEmpty ?? false
        self = isEmpty ? .skipped : .failed
    }
}

struct GraphQLError: Decodable, Sendable {
    let type: String?
    let message: String
}

struct GraphQLResponse<D: Decodable & Sendable>: Decodable, Sendable {
    let data: D?
    let errors: [GraphQLError]?
}

struct WaitingData: Decodable, Sendable {
    struct Search: Decodable, Sendable {
        let issueCount: Int
        let pageInfo: PageInfo
        let nodes: [SearchNode]
    }
    struct RateLimit: Decodable, Sendable { let cost: Int; let remaining: Int }
    let viewer: LoginNode
    let search: Search
    let rateLimit: RateLimit?
}

struct ReviewersData: Decodable, Sendable {
    struct Node: Decodable, Sendable { let reviewRequests: ReviewRequests? }
    let node: Node?
}

struct TeamConnection: Decodable, Sendable {
    struct Team: Decodable, Sendable { let slug: String }
    let nodes: [Team?]
    let pageInfo: PageInfo
}

struct TeamsData: Decodable, Sendable {
    struct Org: Decodable, Sendable {
        let login: String
        let teams: TeamConnection
    }
    struct Orgs: Decodable, Sendable {
        let nodes: [Org?]
        let pageInfo: PageInfo
    }
    struct Viewer: Decodable, Sendable { let organizations: Orgs }
    let viewer: Viewer
}

struct OrgTeamsData: Decodable, Sendable {
    struct Org: Decodable, Sendable { let teams: TeamConnection }
    let organization: Org?
}
