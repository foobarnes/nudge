import Foundation
@testable import NudgeCore
import Testing

@Suite struct GitHubClientTests {
    static func pr() -> JSON {
        prJSON(reviewers: [user("octocat")], events: [requested("RRE_a", "2026-01-05T10:00:00Z", user("octocat"))])
    }

    func client(_ handler: @escaping FakeTransport.Handler) -> (GitHubClient, FakeTransport) {
        let transport = FakeTransport(handler)
        return (GitHubClient(transport: transport, now: { iso("2026-01-05T12:00:00Z") }), transport)
    }

    @Test func paginatesSearchAndRefetchesReviewers() async throws {
        let (client, transport) = client { op, vars, _ in
            switch (op, vars["cursor"]) {
            case ("Waiting", nil):
                .data(waitingPage(nodes: [prJSON(id: "PR_1", number: 1, reviewers: [team("acme", "design")], events: [],
                                                 moreReviewers: "rr1"), [:]], next: "p2"))
            case ("Waiting", "p2"):
                .data(waitingPage(nodes: [prJSON(id: "PR_2", number: 2, reviewers: [user("octocat")], events: [])]))
            case ("Reviewers", "rr1"):
                .data(["node": ["reviewRequests": ["pageInfo": ["hasNextPage": true, "endCursor": "rr2"],
                                                   "nodes": [["requestedReviewer": team("acme", "web")]]]]])
            case ("Reviewers", "rr2"):
                .data(["node": ["reviewRequests": ["pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
                                                   "nodes": [["requestedReviewer": user("octocat")]]]]])
            default: throw SyncError.badResponse("unexpected \(op)")
            }
        }
        let waiting = try await client.fetchWaiting(token: "t")
        #expect(waiting.viewer == "octocat")
        #expect(waiting.nodes.map(\.id) == ["PR_1", "PR_2"])
        #expect(waiting.nodes[0].reviewRequests.nodes.count == 3)
        #expect(waiting.isComplete && !waiting.capped)
        #expect(await transport.count("Reviewers") == 2)
        let prs = ReviewRequestResolver.resolve(nodes: waiting.nodes, viewer: waiting.viewer, teams: [])
        #expect(prs.map(\.prID) == ["PR_1", "PR_2"], "the direct request on reviewer page 3 is found")
    }

    @Test func capsAtFourPages() async throws {
        let (client, transport) = client { _, vars, _ in
            .data(waitingPage(nodes: [], next: (vars["cursor"] ?? "p0") + "+"))
        }
        let waiting = try await client.fetchWaiting(token: "t")
        #expect(waiting.capped)
        #expect(!waiting.isComplete)
        #expect(await transport.count("Waiting") == 4)
    }

    @Test func nullNodeMakesSnapshotIncomplete() async throws {
        let (client, _) = client { _, _, _ in .data(waitingPage(nodes: [Self.pr(), NSNull()])) }
        let waiting = try await client.fetchWaiting(token: "t")
        #expect(waiting.nodes.count == 1)
        #expect(!waiting.isComplete)
    }

    @Test func ssoPartialErrorIsIncompleteWithFix() async throws {
        let (client, _) = client { _, _, _ in
            .data(waitingPage(nodes: [Self.pr(), NSNull()]), errors: [[
                "type": "FORBIDDEN", "path": ["search", "nodes", 1],
                "message": "Resource protected by organization SAML enforcement. You must grant your Personal Access token access to the `acme` organization.",
            ]])
        }
        let waiting = try await client.fetchWaiting(token: "t")
        #expect(!waiting.isComplete)
        #expect(waiting.nodes.count == 1)
        #expect(waiting.sso?.fix == "Authorize SSO for acme: gh auth refresh")
    }

    @Test func mapsErrors() async throws {
        let cases: [(FakeResponse, SyncError)] = [
            (FakeResponse(status: 401, json: ["message": "Bad credentials"]), .unauthorized),
            (FakeResponse(status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1767614400"],
                          json: [:]), .rateLimited(until: Date(timeIntervalSince1970: 1_767_614_400))),
            (FakeResponse(status: 429, headers: ["retry-after": "30"], json: [:]),
             .rateLimited(until: iso("2026-01-05T12:00:30Z"))),
            (FakeResponse(status: 403, json: [:]), .badResponse("HTTP 403")),
            (FakeResponse(status: 502, json: [:]), .badResponse("HTTP 502")),
            (FakeResponse(headers: ["x-ratelimit-reset": "1767614400"],
                          json: ["data": NSNull(), "errors": [["type": "RATE_LIMITED", "message": "API rate limit exceeded"]]]),
             .rateLimited(until: Date(timeIntervalSince1970: 1_767_614_400))),
            (FakeResponse(json: ["errors": [["type": "INSUFFICIENT_SCOPES", "message": "needs read:org"]]]),
             .insufficientScopes),
        ]
        for (response, expected) in cases {
            let (client, _) = client { _, _, _ in response }
            await #expect(throws: expected) { try await client.fetchWaiting(token: "t") }
        }
        let (offline, _) = client { _, _, _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: SyncError.offline) { try await offline.fetchWaiting(token: "t") }
    }

    @Test func problemsCarrySpecFixes() {
        #expect(SyncError.ghMissing.problem.fix == "Install GitHub CLI: brew install gh")
        #expect(SyncError.notLoggedIn.problem.fix == "Run gh auth login")
        #expect(SyncError.insufficientScopes.problem.fix == "Run gh auth refresh -s read:org")
        #expect(SyncError.rateLimited(until: nil).problem.message == "Rate limited by GitHub.")
        #expect(SyncError.rateLimited(until: Date()).problem.message.hasPrefix("Rate limited until "))
    }

    @Test func fetchesTeamsAcrossPages() async throws {
        let (client, transport) = client { op, vars, _ in
            switch (op, vars["orgCursor"]) {
            case ("Teams", nil):
                var page = teamsPage([("acme", ["backend"])], next: "o2")
                var viewer = page["viewer"] as! JSON, orgs = viewer["organizations"] as! JSON
                var nodes = orgs["nodes"] as! [JSON], acme = nodes[0], teams = acme["teams"] as! JSON
                teams["pageInfo"] = ["hasNextPage": true, "endCursor": "t2"]
                acme["teams"] = teams; nodes[0] = acme; orgs["nodes"] = nodes; viewer["organizations"] = orgs
                page["viewer"] = viewer
                return .data(page)
            case ("Teams", "o2"): return .data(teamsPage([("octo-labs", [])]))
            case ("OrgTeams", _):
                #expect(vars["org"] == "acme" && vars["cursor"] == "t2" && vars["login"] == "octocat")
                return .data(["organization": ["teams": ["nodes": [["slug": "platform"]],
                                                         "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]]])
            default: throw SyncError.badResponse(op)
            }
        }
        let teams = try await client.fetchTeams(token: "t", login: "octocat")
        #expect(teams.orgs == ["acme", "octo-labs"])
        #expect(teams.teams == [.team(org: "acme", slug: "backend"), .team(org: "acme", slug: "platform")])
        #expect(await transport.count("Teams") == 2)
    }

    @Test func sendsBearerTokenToGitHubOnly() async throws {
        let (client, _) = client { _, _, token in
            #expect(token == "secret")
            return .data(waitingPage(nodes: []))
        }
        _ = try await client.fetchWaiting(token: "secret")
        #expect(GitHubClient.endpoint.absoluteString == "https://api.github.com/graphql")
    }
}

@Suite struct TokenProviderTests {
    func resolve(_ env: [String: String] = [:], executable: Set<String>, shell: String? = nil) async -> String? {
        await GhTokenProvider.resolveGhPath(environment: env, isExecutable: { executable.contains($0) },
                                            shellLookup: { shell })
    }

    @Test func prefersHomebrew() async {
        #expect(await resolve(executable: ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]) == "/opt/homebrew/bin/gh")
        #expect(await resolve(executable: ["/usr/local/bin/gh"]) == "/usr/local/bin/gh")
    }

    @Test func fallsBackToLoginShell() async {
        #expect(await resolve(executable: ["/nix/bin/gh"], shell: "/nix/bin/gh\n") == "/nix/bin/gh")
        #expect(await resolve(executable: [], shell: "gh: aliased to hub") == nil)
        #expect(await resolve(executable: []) == nil)
    }

    @Test func debugOverrideReplacesSearch() async {
        #expect(await resolve(["NUDGE_GH_PATH": "/nonexistent"], executable: ["/opt/homebrew/bin/gh"]) == nil)
        #expect(await resolve(["NUDGE_GH_PATH": "/tmp/gh"], executable: ["/tmp/gh"]) == "/tmp/gh")
    }
}
