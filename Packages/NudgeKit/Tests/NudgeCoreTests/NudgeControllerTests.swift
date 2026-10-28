import Foundation
@testable import NudgeCore
import Testing

@MainActor @Suite struct NudgeControllerTests {
    let defaults = freshDefaults()
    let now = at("2026-01-06 17:00") // Tuesday

    func controller(_ fixture: String = "four-prs.json", state: NudgeState = NudgeState()) -> NudgeController {
        let now = now
        return NudgeController(state: state, store: Store(defaults: defaults), source: .fixture(fixtureURL(fixture)),
                               now: { now }, calendar: newYork)
    }

    @Test func fixtureDrivesRowsWithoutGitHub() {
        let c = controller()
        var posted: [PlannedNotification] = []
        c.onNotify = { posted.append($0) }
        c.start()
        defer { c.stop() }
        let s = c.state
        #expect(s.rows.map(\.pr.number) == [4188, 4211, 930, 88], "oldest first")
        #expect(s.rows.map(\.tier) == [.red, .amber, .fresh, .fresh])
        #expect(s.rows[0].workSeconds == 39_600)
        #expect(s.rows[0].workSecondsToNextTier == nil)
        #expect(s.rows[1].workSecondsToNextTier == 10_800)
        #expect(s.rows[3].pr.via == .team(org: "acme", slug: "backend"))
        #expect(s.viewerLogin == "octocat")
        #expect(s.knownOrgs.map(\.login) == ["acme", "octocat"])
        #expect(s.knownOrgs.first?.waitingCount == 4)
        #expect(!s.isOffHours)
        #expect(s.status == .ok(lastSync: now))
        #expect(posted.isEmpty, "first launch seeds silently")
        #expect(s.newRequestPulse == 0)
    }

    @Test func zeroAndThreeFixtures() {
        let zero = controller("zero-prs.json")
        zero.start()
        zero.stop()
        #expect(zero.state.rows.isEmpty)
        let three = controller("three-prs.json")
        three.start()
        three.stop()
        #expect(three.state.rows.count == 3)
    }

    @Test func newRequestNotifiesAndPulses() {
        let c = controller("zero-prs.json")
        var posted: [PlannedNotification] = []
        c.onNotify = { posted.append($0) }
        c.start()
        c.stop()
        let pr = makePR(requestedBy: "bo", waitingSince: now)
        c.apply(.synced(SyncResult(snapshot: SyncSnapshot(prs: [pr], isComplete: true, fetchedAt: now),
                                   viewer: "octocat", orgs: ["acme"], capped: true, notice: nil)))
        #expect(posted.map(\.title) == ["bo requested your review"])
        #expect(c.state.newRequestPulse == 1)
        #expect(c.state.resultsCapped)
        #expect(c.row(withID: "RRE_a")?.pr == pr)
    }

    @Test func snoozeUnsnoozeHidePersist() throws {
        let c = controller()
        c.start()
        c.stop()
        let row = try #require(c.state.rows.first)
        c.snooze(row, .minutes(60))
        #expect(c.state.rows.count == 3)
        #expect(c.state.snoozedRows.map(\.id) == [row.id])
        #expect(c.state.snoozedRows.first?.snoozedUntil == now.addingTimeInterval(3600))
        #expect(c.row(withID: row.id) != nil)
        c.unsnooze(c.state.snoozedRows[0])
        #expect(c.state.rows.count == 4)
        c.hide(c.state.rows[1])
        #expect(c.state.rows.map(\.pr.number) == [4188, 930, 88])

        let relaunched = controller()
        relaunched.start()
        relaunched.stop()
        #expect(relaunched.state.rows.map(\.pr.number) == [4188, 930, 88])
    }

    @Test func settingsPersistAndRulesApply() {
        let c = controller()
        c.start()
        c.stop()
        c.updateSettings { $0.repoRules["acme/api"] = .hidden; $0.orgRules["acme"] = .silent }
        #expect(c.state.rows.map(\.pr.number) == [930, 88])
        #expect(c.state.rows.allSatisfy { $0.level == .silent })
        #expect(Store(defaults: defaults).loadSettings().repoRules == ["acme/api": .hidden])
        let next = NudgeState()
        _ = controller(state: next)
        #expect(next.settings.orgRules == ["acme": .silent])
    }

    @Test func noticeFollowsEachSync() {
        let c = controller("zero-prs.json")
        c.start()
        c.stop()
        let sso = SyncError.ssoProblem(org: "acme")
        func sync(_ notice: SyncProblem?) {
            c.apply(.synced(SyncResult(snapshot: SyncSnapshot(prs: [], isComplete: notice == nil, fetchedAt: now),
                                       viewer: "octocat", orgs: [], capped: false, notice: notice)))
        }
        sync(sso)
        #expect(c.state.notice?.fix == "Authorize SSO for acme: gh auth refresh")
        sync(nil)
        #expect(c.state.notice == nil)
    }

    @Test func authFailureNotifiesOncePerEpisode() {
        let c = controller()
        var posted: [PlannedNotification] = []
        c.onNotify = { posted.append($0) }
        c.start()
        c.stop()
        c.apply(.failed(.notLoggedIn))
        c.apply(.failed(.notLoggedIn))
        #expect(posted.map(\.kind) == [.authProblem])
        #expect(c.state.status == .stale(lastSync: now, problem: SyncError.notLoggedIn.problem))
        #expect(c.state.rows.count == 4, "rows stay while stale")
    }
}

@Suite struct FixtureLoaderTests {
    @Test func loadsRelativeAges() throws {
        let now = Date()
        let prs = try FixtureLoader.load(fixtureURL("four-prs.json"), now: now)
        #expect(prs.map(\.title) == ["Rate-limit retries for webhooks", "Fix token refresh race",
                                     "Export reports to CSV", "Bump build dependencies"])
        #expect(prs[0].waitingSince == now.addingTimeInterval(-93_600))
        #expect(prs[3].via == .team(org: "acme", slug: "backend"))
        #expect(prs[3].url.absoluteString == "https://github.com/acme/infra/pull/88")
        #expect(try FixtureLoader.load(fixtureURL("zero-prs.json")).isEmpty)
    }

    @Test func unknownTimeWhenAgeMissing() {
        let entry = FixtureLoader.Entry(repo: "acme/api", number: 1, title: "t", author: "alice")
        let pr = FixtureLoader.waitingPR(entry, now: Date())
        #expect(pr.waitingSince == nil)
        #expect(pr.requestKey.hasSuffix("#direct#unknown"))
    }
}
