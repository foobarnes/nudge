import Foundation
import os

protocol GraphQLTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: GraphQLTransport {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.badResponse("not HTTP") }
        return (data, http)
    }
}

struct GitHubClient: Sendable {
    static let endpoint = URL(string: "https://api.github.com/graphql")!
    static let maxSearchPages = 4

    struct Waiting: Sendable {
        let viewer: String
        let nodes: [PRNode]
        let isComplete: Bool
        let capped: Bool
        let sso: SyncProblem?
    }

    struct Teams: Sendable {
        let teams: Set<RequestTarget>
        let orgs: [String]
    }

    let transport: GraphQLTransport
    var now: @Sendable () -> Date = { Date() }
    private static let log = Logger(subsystem: "io.github.foobarnes.nudge", category: "github")

    // MARK: Queries

    func fetchWaiting(token: String) async throws -> Waiting {
        var nodes: [PRNode] = [], viewer = "", cursor: String?
        var complete = true, capped = false, errors: [GraphQLError] = []
        for page in 1...Self.maxSearchPages {
            let (data, pageErrors) = try await query(Self.waitingQuery, ["cursor": cursor], token: token,
                                                     as: WaitingData.self)
            viewer = data.viewer.login
            errors += pageErrors
            if let cost = data.rateLimit { Self.log.debug("search page cost \(cost.cost), remaining \(cost.remaining)") }
            for node in data.search.nodes {
                switch node {
                case let .pr(pr): nodes.append(pr)
                case .failed: complete = false
                case .skipped: break
                }
            }
            guard data.search.pageInfo.hasNextPage, let next = data.search.pageInfo.endCursor else { break }
            if page == Self.maxSearchPages { capped = true; break }
            cursor = next
        }
        for i in nodes.indices where nodes[i].reviewRequests.pageInfo.hasNextPage {
            do {
                nodes[i].reviewRequests = try await allReviewers(nodes[i], token: token)
            } catch SyncError.badResponse {
                complete = false
            }
        }
        return Waiting(viewer: viewer, nodes: nodes, isComplete: complete && errors.isEmpty && !capped, capped: capped,
                       sso: Self.ssoProblem(errors))
    }

    private func allReviewers(_ pr: PRNode, token: String) async throws -> ReviewRequests {
        var requests = pr.reviewRequests
        while requests.pageInfo.hasNextPage, let cursor = requests.pageInfo.endCursor {
            let (data, errors) = try await query(Self.reviewersQuery, ["id": pr.id, "cursor": cursor], token: token,
                                                 as: ReviewersData.self)
            guard errors.isEmpty, let more = data.node?.reviewRequests else {
                throw SyncError.badResponse("reviewer page")
            }
            requests.nodes += more.nodes
            requests.pageInfo = more.pageInfo
        }
        return requests
    }

    func fetchTeams(token: String, login: String) async throws -> Teams {
        var teams = Set<RequestTarget>(), orgs: [String] = [], cursor: String?
        repeat {
            let (data, _) = try await query(Self.teamsQuery, ["login": login, "orgCursor": cursor], token: token,
                                            as: TeamsData.self)
            for org in data.viewer.organizations.nodes.compactMap({ $0 }) {
                orgs.append(org.login)
                var connection = org.teams
                while true {
                    for team in connection.nodes.compactMap({ $0 }) { teams.insert(.team(org: org.login, slug: team.slug)) }
                    guard connection.pageInfo.hasNextPage, let next = connection.pageInfo.endCursor else { break }
                    let (more, _) = try await query(Self.orgTeamsQuery, ["org": org.login, "login": login, "cursor": next],
                                                    token: token, as: OrgTeamsData.self)
                    guard let teams = more.organization?.teams else { break }
                    connection = teams
                }
            }
            let info = data.viewer.organizations.pageInfo
            cursor = info.hasNextPage ? info.endCursor : nil
        } while cursor != nil
        return Teams(teams: teams, orgs: orgs)
    }

    // MARK: Transport and error mapping

    private struct Body: Encodable {
        let query: String
        let variables: [String: String?]
    }

    func query<D: Decodable & Sendable>(_ query: String, _ variables: [String: String?], token: String,
                                        as type: D.Type) async throws -> (D, [GraphQLError]) {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(query: query, variables: variables))

        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.offline
        }

        switch response.statusCode {
        case 200: break
        case 401: throw SyncError.unauthorized
        case 403, 429:
            if let limit = rateLimit(response) { throw SyncError.rateLimited(until: limit.until) }
            if response.statusCode == 429 { throw SyncError.rateLimited(until: nil) }
            throw SyncError.badResponse("HTTP \(response.statusCode)")
        default: throw SyncError.badResponse("HTTP \(response.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let body = try? decoder.decode(GraphQLResponse<D>.self, from: data) else {
            throw SyncError.badResponse("unreadable JSON")
        }
        let errors = body.errors ?? []
        if errors.contains(where: { $0.type == "RATE_LIMITED" }) {
            let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
            throw SyncError.rateLimited(until: rateLimit(response)?.until ?? reset.map(Date.init(timeIntervalSince1970:)))
        }
        if errors.contains(where: { $0.type == "INSUFFICIENT_SCOPES" }) { throw SyncError.insufficientScopes }
        guard let payload = body.data else { throw SyncError.badResponse(errors.first?.message ?? "no data") }
        return (payload, errors)
    }

    private struct RateLimit { let until: Date? }

    /// Non-nil when the headers say the request was rate limited: `retry-after` seconds, or an exhausted
    /// `x-ratelimit-remaining` with its `x-ratelimit-reset` epoch.
    private func rateLimit(_ response: HTTPURLResponse) -> RateLimit? {
        if let retry = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) {
            return RateLimit(until: now().addingTimeInterval(retry))
        }
        guard response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" else { return nil }
        let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
        return RateLimit(until: reset.map(Date.init(timeIntervalSince1970:)))
    }

    static func ssoProblem(_ errors: [GraphQLError]) -> SyncProblem? {
        guard let message = errors.first(where: { $0.message.contains("SAML") })?.message else { return nil }
        let org = message.firstMatch(of: #/`([\w.-]+)` organization/#)?.1
        return SyncError.ssoProblem(org: org.map(String.init))
    }

    // MARK: Query text

    static let waitingQuery = """
    query Waiting($cursor: String) {
      viewer { login }
      search(query: "is:open is:pr archived:false review-requested:@me", type: ISSUE, first: 50, after: $cursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes { ... on PullRequest {
          id number title url isDraft headRefName author { login }
          repository { nameWithOwner }
          reviewRequests(first: 100) { pageInfo { hasNextPage endCursor } nodes { requestedReviewer {
            __typename ... on User { login } ... on Team { slug organization { login } } } } }
          timelineItems(last: 50, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT]) { nodes {
            __typename
            ... on ReviewRequestedEvent { id createdAt actor { login } requestedReviewer {
              __typename ... on User { login } ... on Team { slug organization { login } } } }
            ... on ReadyForReviewEvent { createdAt } } }
        } }
      }
      rateLimit { cost remaining resetAt }
    }
    """

    static let reviewersQuery = """
    query Reviewers($id: ID!, $cursor: String) {
      node(id: $id) { ... on PullRequest {
        reviewRequests(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor }
          nodes { requestedReviewer { __typename ... on User { login } ... on Team { slug organization { login } } } } } } }
    }
    """

    static let teamsQuery = """
    query Teams($login: String!, $orgCursor: String) {
      viewer {
        organizations(first: 100, after: $orgCursor) {
          nodes { login teams(first: 100, userLogins: [$login]) { nodes { slug } pageInfo { hasNextPage endCursor } } }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

    static let orgTeamsQuery = """
    query OrgTeams($org: String!, $login: String!, $cursor: String) {
      organization(login: $org) {
        teams(first: 100, after: $cursor, userLogins: [$login]) { nodes { slug } pageInfo { hasNextPage endCursor } }
      }
    }
    """
}
