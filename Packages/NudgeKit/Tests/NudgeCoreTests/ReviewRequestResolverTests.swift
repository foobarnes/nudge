import Foundation
@testable import NudgeCore
import Testing

/// One test per row of the spec's resolver table (viewer octocat, member of acme/backend and acme/platform).
@Suite struct ReviewRequestResolverTests {
    let myTeams: Set<RequestTarget> = [.team(org: "acme", slug: "backend"), .team(org: "acme", slug: "platform")]

    func resolve(_ json: JSON) throws -> WaitingPR? {
        ReviewRequestResolver.resolve(nodes: [try decodePR(json)], viewer: "octocat", teams: myTeams).first
    }

    @Test func reRequestAfterReview() throws {
        let pr = try #require(try resolve(prJSON(reviewers: [user("octocat")], events: [
            requested("RRE_a", "2026-01-05T10:00:00Z", user("octocat")),
            ready("2026-01-05T10:15:00Z"),
            requested("RRE_b", "2026-01-05T11:00:00Z", user("octocat")),
        ])))
        #expect(pr.requestKey == "RRE_b")
        #expect(pr.waitingSince == iso("2026-01-05T11:00:00Z"))
        #expect(pr.via == .direct)
        #expect(pr.requestedBy == "alice")
    }

    @Test func requestedWhileDraftThenReady() throws {
        let pr = try #require(try resolve(prJSON(reviewers: [user("octocat")], events: [
            requested("RRE_a", "2026-01-05T10:00:00Z", user("octocat")),
            ready("2026-01-05T10:15:00Z"),
        ])))
        #expect(pr.requestKey == "RRE_a")
        #expect(pr.waitingSince == iso("2026-01-05T10:15:00Z"))
        #expect(pr.requestedAt == iso("2026-01-05T10:00:00Z"))
    }

    @Test func draftExcluded() throws {
        #expect(try resolve(prJSON(draft: true, reviewers: [user("octocat")], events: [
            requested("RRE_a", "2026-01-05T10:00:00Z", user("octocat")),
        ])) == nil)
    }

    @Test func teamRequestOnly() throws {
        let pr = try #require(try resolve(prJSON(reviewers: [team("acme", "backend")], events: [
            requested("RRE_t1", "2026-01-05T09:00:00Z", team("acme", "backend")),
            requested("RRE_x", "2026-01-05T09:30:00Z", user("bo")),
            requested("RRE_t2", "2026-01-05T10:00:00Z", team("acme", "backend")),
        ])))
        #expect(pr.via == .team(org: "acme", slug: "backend"))
        #expect(pr.requestKey == "RRE_t2")
        #expect(pr.otherTeams.isEmpty)
    }

    @Test func twoOfMyTeams() throws {
        let pr = try #require(try resolve(prJSON(reviewers: [team("acme", "backend"), team("acme", "platform")], events: [
            requested("RRE_b", "2026-01-05T10:00:00Z", team("acme", "backend")),
            requested("RRE_p", "2026-01-05T10:30:00Z", team("acme", "platform")),
        ])))
        #expect(pr.via == .team(org: "acme", slug: "platform"))
        #expect(pr.otherTeams == [.team(org: "acme", slug: "backend")])
        #expect(pr.waitingSince == iso("2026-01-05T10:30:00Z"))
    }

    @Test func directBeatsTeam() throws {
        let pr = try #require(try resolve(prJSON(reviewers: [team("acme", "backend"), user("octocat")], events: [
            requested("RRE_d", "2026-01-05T09:00:00Z", user("octocat")),
            requested("RRE_t", "2026-01-05T10:00:00Z", team("acme", "backend")),
        ])))
        #expect(pr.via == .direct)
        #expect(pr.requestKey == "RRE_d")
        #expect(pr.waitingSince == iso("2026-01-05T09:00:00Z"))
        #expect(pr.otherTeams == [.team(org: "acme", slug: "backend")])
    }

    @Test func directRemovedTeamRemains() throws {
        let events = [requested("RRE_t", "2026-01-05T09:00:00Z", team("acme", "backend")),
                      requested("RRE_d", "2026-01-05T10:00:00Z", user("octocat"))]
        let before = try #require(try resolve(prJSON(reviewers: [user("octocat"), team("acme", "backend")], events: events)))
        let after = try #require(try resolve(prJSON(reviewers: [team("acme", "backend")], events: events)))
        #expect(before.requestKey == "RRE_d")
        #expect(after.requestKey == "RRE_t")
        #expect(after.via == .team(org: "acme", slug: "backend"))
        #expect(after.requestedAt! < before.requestedAt!, "older event, so the planner migrates silently")
    }

    @Test func noMatchingEvent() throws {
        let pr = try #require(try resolve(prJSON(reviewers: [user("octocat")], events: [
            requested("RRE_x", "2026-01-05T10:00:00Z", user("bo")),
        ])))
        #expect(pr.requestKey == "PR_example1#direct#unknown")
        #expect(pr.waitingSince == nil)
        #expect(pr.requestedBy == nil)
    }

    @Test func unknownTeamKey() throws {
        let pr = try #require(try resolve(prJSON(reviewers: [team("acme", "backend")], events: [])))
        #expect(pr.requestKey == "PR_example1#acme/backend#unknown")
    }

    @Test func botReviewerSkipped() throws {
        #expect(try resolve(prJSON(reviewers: [bot("ci-bot")], events: [])) == nil)
        #expect(try resolve(prJSON(reviewers: [user("bo"), team("acme", "design")], events: [])) == nil)
    }

    @Test func nullActorKept() throws {
        let pr = try #require(try resolve(prJSON(reviewers: [user("octocat")], events: [
            requested("RRE_g", "2026-01-05T10:00:00Z", actor: nil, user("octocat")),
        ])))
        #expect(pr.requestKey == "RRE_g")
        #expect(pr.requestedBy == nil)
        #expect(NotificationPlanner.banner(pr).title == "Review requested")
    }

    @Test func matchingIgnoresCase() throws {
        let pr = try resolve(prJSON(reviewers: [user("OctoCat"), team("Acme", "Backend")], events: [
            requested("RRE_a", "2026-01-05T10:00:00Z", user("OCTOCAT")),
        ]))
        #expect(pr?.requestKey == "RRE_a")
    }
}
