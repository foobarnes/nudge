import Foundation
@testable import NudgeCore
import Synchronization
import Testing

@Suite struct SyncEngineTests {
    final class Updates: Sendable {
        private let value = Mutex<[SyncUpdate]>([])
        var all: [SyncUpdate] { value.withLock { $0 } }
        func append(_ update: SyncUpdate) { value.withLock { $0.append(update) } }
        var viewers: [String] {
            all.compactMap { if case let .synced(r) = $0 { r.viewer } else { nil } }
        }
        var errors: [SyncError] {
            all.compactMap { if case let .failed(e) = $0 { e } else { nil } }
        }
    }

    let clock = TestClock(iso("2026-01-05T15:00:00Z"))
    let updates = Updates()
    static func pr() -> JSON {
        prJSON(reviewers: [team("acme", "backend")],
               events: [requested("RRE_t", "2026-01-05T10:00:00Z", team("acme", "backend"))])
    }

    func engine(tokens: FakeTokens = FakeTokens(), _ handler: @escaping FakeTransport.Handler)
        -> (SyncEngine, FakeTransport) {
        let transport = FakeTransport(handler)
        let clock = clock, updates = updates
        let engine = SyncEngine(tokens: tokens, client: GitHubClient(transport: transport, now: { clock.now }),
                                now: { clock.now }, deliver: { updates.append($0) })
        return (engine, transport)
    }

    func ok(viewer: String = "octocat") -> FakeTransport.Handler {
        return { op, _, _ in
            op == "Waiting" ? .data(waitingPage(viewer: viewer, nodes: [Self.pr()])) : .data(teamsPage([("acme", ["backend"])]))
        }
    }

    @Test func resolvesTeamRequestsWithTeamCache() async throws {
        let (engine, transport) = engine(ok())
        await engine.trigger(.launch)
        guard case let .synced(result) = try #require(updates.all.first) else { Issue.record("no sync"); return }
        #expect(result.snapshot.prs.map(\.via) == [.team(org: "acme", slug: "backend")])
        #expect(result.snapshot.isComplete)
        #expect(result.snapshot.fetchedAt == clock.now)
        #expect(result.orgs == ["acme"])

        clock.advance(60)
        await engine.trigger(.timer)
        #expect(await transport.count("Teams") == 1, "cached within the hour")
        clock.advance(3600)
        await engine.trigger(.timer)
        #expect(await transport.count("Teams") == 2, "refreshed hourly")
    }

    @Test func accountSwitchRefetchesTeams() async {
        let viewer = Mutex("octocat")
        let (engine, transport) = engine { op, _, _ in
            op == "Waiting" ? .data(waitingPage(viewer: viewer.withLock { $0 }, nodes: [Self.pr()]))
                            : .data(teamsPage([("acme", ["backend"])]))
        }
        await engine.trigger(.launch)
        viewer.withLock { $0 = "alice" }
        clock.advance(60)
        await engine.trigger(.timer)
        #expect(updates.viewers == ["octocat", "alice"])
        #expect(await transport.count("Teams") == 2)
    }

    @Test func singleFlightWithOneFollowUp() async throws {
        let (engine, transport) = engine(ok())
        await transport.pause()
        let first = Task { await engine.trigger(.launch) }
        while await transport.count("Waiting") == 0 { await Task.yield() }
        await engine.trigger(.wake)
        await engine.trigger(.timer)
        await engine.trigger(.manual)
        await transport.resume()
        await first.value
        #expect(await transport.count("Waiting") == 2)
        #expect(updates.all.count == 2)
    }

    @Test func manualSyncCooldown() async {
        let (engine, transport) = engine(ok())
        await engine.trigger(.manual)
        clock.advance(5)
        await engine.trigger(.manual)
        #expect(await transport.count("Waiting") == 1)
        clock.advance(6)
        await engine.trigger(.manual)
        #expect(await transport.count("Waiting") == 2)
    }

    @Test func backoffThenReset() async {
        let failing = Mutex(true)
        let ok = ok()
        let (engine, _) = engine { op, vars, token in
            if failing.withLock({ $0 }) { throw URLError(.timedOut) }
            return try ok(op, vars, token)
        }
        #expect(await engine.nextDelay() == 15)
        var delays: [TimeInterval] = []
        for _ in 0..<4 {
            await engine.trigger(.timer)
            delays.append(await engine.nextDelay())
        }
        #expect(delays == [60, 120, 300, 300])
        #expect(updates.errors == Array(repeating: .offline, count: 4))
        failing.withLock { $0 = false }
        await engine.trigger(.timer)
        #expect(await engine.nextDelay() == 15)
    }

    @Test func rateLimitBlocksUntilReset() async {
        let limited = Mutex(true)
        let ok = ok()
        let (engine, transport) = engine { op, vars, token in
            if limited.withLock({ $0 }) { return FakeResponse(status: 429, headers: ["retry-after": "600"], json: [:]) }
            return try ok(op, vars, token)
        }
        await engine.trigger(.launch)
        #expect(updates.errors == [.rateLimited(until: clock.now.addingTimeInterval(600))])
        #expect(await engine.nextDelay() == 600)
        limited.withLock { $0 = false }
        clock.advance(300)
        await engine.trigger(.manual)
        await engine.trigger(.wake)
        #expect(await transport.count("Waiting") == 1)
        clock.advance(301)
        await engine.trigger(.timer)
        #expect(await transport.count("Waiting") == 2)
    }

    @Test func unauthorizedRereadsTokenOnce() async {
        let tokens = FakeTokens(["old", "new"])
        let ok = ok()
        let (engine, _) = engine(tokens: tokens) { op, vars, token in
            token == "old" ? FakeResponse(status: 401, json: [:]) : try ok(op, vars, token)
        }
        await engine.trigger(.launch)
        #expect(updates.viewers == ["octocat"])
        #expect(await tokens.refreshes == 1)
    }

    @Test func unauthorizedTwiceIsNotLoggedIn() async {
        let (engine, _) = engine { _, _, _ in FakeResponse(status: 401, json: [:]) }
        await engine.trigger(.launch)
        #expect(updates.errors == [.notLoggedIn])
    }

    @Test func stopDiscardsInFlightResult() async {
        let (engine, transport) = engine(ok())
        await transport.pause()
        let first = Task { await engine.trigger(.launch) }
        while await transport.count("Waiting") == 0 { await Task.yield() }
        await engine.stop()
        await transport.resume()
        await first.value
        #expect(updates.all.isEmpty)
    }
}
