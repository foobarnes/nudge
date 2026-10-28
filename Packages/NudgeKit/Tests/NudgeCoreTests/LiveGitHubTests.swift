import Foundation
@testable import NudgeCore
import Testing

/// Read-only smoke test against api.github.com with the local `gh` login. Prints shapes and counts only.
/// Run with `NUDGE_LIVE=1 swift test --filter LiveGitHubTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NUDGE_LIVE"] == "1"))
struct LiveGitHubTests {
    @Test func fetchAndResolve() async throws {
        let token = try await GhTokenProvider().token(refresh: false)
        let client = GitHubClient(transport: URLSessionTransport())
        let waiting = try await client.fetchWaiting(token: token)
        let teams = try await client.fetchTeams(token: token, login: waiting.viewer)
        let prs = ReviewRequestResolver.resolve(nodes: waiting.nodes, viewer: waiting.viewer, teams: teams.teams)
        let direct = prs.filter { $0.via == .direct }.count
        print("""
        [live] search PRs: \(waiting.nodes.count), drafts: \(waiting.nodes.filter(\.isDraft).count), waiting: \(prs.count)
        [live] isComplete: \(waiting.isComplete), capped: \(waiting.capped), sso: \(waiting.sso != nil)
        [live] cost per page: \(waiting.pageCosts)
        [live] via direct: \(direct), via team: \(prs.count - direct), with otherTeams: \(prs.filter { !$0.otherTeams.isEmpty }.count)
        [live] waitingSince set: \(prs.map { $0.waitingSince != nil }), actor set: \(prs.map { $0.requestedBy != nil })
        [live] orgs: \(teams.orgs.count), teams: \(teams.teams.count)
        """)
        #expect(!waiting.viewer.isEmpty)
    }
}
