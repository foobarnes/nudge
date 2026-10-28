import Foundation
@testable import NudgeCore
import Synchronization

// Builders for synthetic GraphQL JSON in the shape of the spec's representative response.

typealias JSON = [String: Any]

func user(_ login: String) -> JSON { ["__typename": "User", "login": login] }
func team(_ org: String, _ slug: String) -> JSON { ["__typename": "Team", "slug": slug, "organization": ["login": org]] }
func bot(_ login: String) -> JSON { ["__typename": "Bot", "login": login] }

func requested(_ id: String, _ time: String, actor: String? = "alice", _ reviewer: JSON) -> JSON {
    ["__typename": "ReviewRequestedEvent", "id": id, "createdAt": time,
     "actor": actor.map { ["login": $0] as Any } ?? NSNull(), "requestedReviewer": reviewer]
}

func orNull(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }

func ready(_ time: String) -> JSON { ["__typename": "ReadyForReviewEvent", "createdAt": time] }

func prJSON(id: String = "PR_example1", number: Int = 4211, draft: Bool = false, botAuthor: Bool = false,
            reviewers: [JSON], events: [JSON], moreReviewers: String? = nil) -> JSON {
    ["id": id, "number": number, "title": "Fix token refresh", "url": "https://github.com/acme/api/pull/\(number)",
     "isDraft": draft, "headRefName": "fix-refresh", "author": ["__typename": botAuthor ? "Bot" : "User", "login": "alice"],
     "repository": ["nameWithOwner": "acme/api"],
     "reviewRequests": ["pageInfo": ["hasNextPage": moreReviewers != nil, "endCursor": orNull(moreReviewers)],
                        "nodes": reviewers.map { ["requestedReviewer": $0] }],
     "timelineItems": ["nodes": events]]
}

func decodePR(_ json: JSON) throws -> PRNode {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(PRNode.self, from: JSONSerialization.data(withJSONObject: json))
}

func iso(_ text: String) -> Date { try! Date(text, strategy: .iso8601) }

// MARK: Fake network

struct FakeResponse: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body: Data

    init(status: Int = 200, headers: [String: String] = [:], json: Any) {
        self.status = status; self.headers = headers
        body = try! JSONSerialization.data(withJSONObject: json)
    }

    static func data(_ data: JSON, errors: [JSON]? = nil) -> FakeResponse {
        var json: JSON = ["data": data]
        if let errors { json["errors"] = errors }
        return FakeResponse(json: json)
    }
}

func waitingPage(viewer: String = "octocat", nodes: [Any], next: String? = nil) -> JSON {
    ["viewer": ["login": viewer],
     "search": ["issueCount": nodes.count, "pageInfo": ["hasNextPage": next != nil, "endCursor": orNull(next)],
                "nodes": nodes],
     "rateLimit": ["cost": 1, "remaining": 4999, "resetAt": "2026-01-05T11:00:00Z"]]
}

func teamsPage(_ orgs: [(String, [String])], next: String? = nil) -> JSON {
    ["viewer": ["organizations": [
        "nodes": orgs.map { org, slugs in
            ["login": org, "teams": ["nodes": slugs.map { ["slug": $0] },
                                     "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]] },
        "pageInfo": ["hasNextPage": next != nil, "endCursor": orNull(next)]]]]
}

/// Routes requests by GraphQL operation name to a handler and records each call.
actor FakeTransport: GraphQLTransport {
    typealias Handler = @Sendable (_ operation: String, _ variables: [String: String], _ token: String) throws -> FakeResponse
    private let handler: Handler
    private(set) var calls: [(operation: String, variables: [String: String])] = []
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ handler: @escaping Handler) { self.handler = handler }

    func count(_ operation: String) -> Int { calls.filter { $0.operation == operation }.count }

    /// While paused, `Waiting` requests block until `resume()`.
    func pause() { paused = true }
    func resume() {
        paused = false
        waiters.forEach { $0.resume() }
        waiters = []
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! JSON
        let query = body["query"] as! String
        let operation = String(query.split(separator: " ")[1].prefix { $0.isLetter })
        let variables = (body["variables"] as? JSON ?? [:]).compactMapValues { $0 as? String }
        let token = request.value(forHTTPHeaderField: "Authorization")!.replacingOccurrences(of: "bearer ", with: "")
        calls.append((operation, variables))
        if operation == "Waiting", paused { await withCheckedContinuation { waiters.append($0) } }
        let response = try handler(operation, variables, token)
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil,
                                   headerFields: response.headers)!
        return (response.body, http)
    }
}

final class TestClock: Sendable {
    private let value: Mutex<Date>
    init(_ start: Date) { value = Mutex(start) }
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

actor FakeTokens: TokenProviding {
    private let tokens: [String]
    private var index = 0
    private(set) var refreshes = 0
    init(_ tokens: [String] = ["t1", "t2", "t3"]) { self.tokens = tokens }

    /// Each refresh moves to the next token.
    func token(refresh: Bool) async throws -> String {
        if refresh {
            refreshes += 1
            index = min(index + 1, tokens.count - 1)
        }
        return tokens[index]
    }
}
