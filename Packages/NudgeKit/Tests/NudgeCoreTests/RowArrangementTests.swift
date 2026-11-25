import Foundation
@testable import NudgeCore
import Testing

@Suite struct RowArrangementTests {
    let now = at("2026-01-09 17:00")

    /// Oldest-first, as `NudgeController` hands rows over.
    var rows: [PRRow] {
        [
            row("a", repo: "acme/api", hoursAgo: 30, tier: .red, diff: (300, 20, 9), author: "alice"),
            row("b", repo: "zeta/web", hoursAgo: 10, tier: .amber, diff: (4, 1, 1), author: "bo"),
            row("c", repo: "acme/api", hoursAgo: 5, tier: .fresh, diff: nil, author: "alice"),
            row("d", repo: "acme/infra", hoursAgo: 1, tier: .fresh, diff: (40, 0, 3), author: "bo"),
        ]
    }

    func ids(_ sort: RowSort) -> [String] {
        RowArrangement.arrange(rows, sort: sort, group: .none).flatMap(\.rows).map(\.pr.prID)
    }

    @Test func sorts() {
        #expect(ids(.longestWaiting) == ["a", "b", "c", "d"])
        #expect(ids(.newest) == ["d", "c", "b", "a"])
        #expect(ids(.smallestDiff) == ["b", "d", "a", "c"])   // no diff: last
        #expect(ids(.largestDiff) == ["a", "d", "b", "c"])    // still last
        #expect(ids(.fewestFiles) == ["b", "d", "a", "c"])
        #expect(ids(.mostFiles) == ["a", "d", "b", "c"])
        #expect(ids(.repository) == ["a", "c", "d", "b"])     // ties keep oldest-first
    }

    @Test func noGroupingIsOneHeaderlessGroup() {
        let groups = RowArrangement.arrange(rows, sort: .longestWaiting, group: .none)
        #expect(groups.map(\.key) == [.all])
        #expect(RowArrangement.arrange([], sort: .longestWaiting, group: .repository).isEmpty)
    }

    @Test func groupsFollowTheSort() {
        let byRepo = RowArrangement.arrange(rows, sort: .longestWaiting, group: .repository)
        #expect(byRepo.map(\.key) == [.repository("acme/api"), .repository("zeta/web"), .repository("acme/infra")])
        #expect(byRepo[0].rows.map(\.pr.prID) == ["a", "c"])

        let newestByOwner = RowArrangement.arrange(rows, sort: .newest, group: .owner)
        #expect(newestByOwner.map(\.key) == [.owner("acme"), .owner("zeta")])
        #expect(newestByOwner[0].rows.map(\.pr.prID) == ["d", "c", "a"])
    }

    @Test func groupKeys() {
        #expect(RowArrangement.arrange(rows, sort: .longestWaiting, group: .urgency).map(\.key)
                == [.tier(.red), .tier(.amber), .tier(.fresh)])
        #expect(RowArrangement.arrange(rows, sort: .smallestDiff, group: .size).map(\.key)
                == [.size(.xs), .size(.s), .size(.l), .size(nil)])
        #expect(RowArrangement.arrange(rows, sort: .longestWaiting, group: .author).map(\.key)
                == [.author("alice"), .author("bo")])
    }

    @Test func sizeBuckets() {
        #expect([0, 9, 10, 49, 50, 249, 250, 999, 1000].map(DiffSize.init(lines:))
                == [.xs, .xs, .s, .s, .m, .m, .l, .l, .xl])
    }

    @MainActor @Test func stateKeepsOldestFirstForThePill() {
        let state = NudgeState()
        state.rows = rows
        state.settings.sortBy = .newest
        #expect(state.oldest?.pr.prID == "a")
        #expect(state.orderedRows.map(\.pr.prID) == ["d", "c", "b", "a"])
    }

    private func row(_ id: String, repo: String, hoursAgo: Double, tier: Tier, diff: (Int, Int, Int)?,
                     author: String) -> PRRow {
        let since = now.addingTimeInterval(-hoursAgo * 3600)
        let pr = WaitingPR(prID: id, repo: repo, number: 1, title: id, url: URL(string: "https://github.com/\(repo)/pull/1")!,
                           author: author, headRef: id, via: .direct, requestedBy: nil, requestKey: id,
                           requestedAt: since, waitingSince: since,
                           diff: diff.map { DiffStat(additions: $0.0, deletions: $0.1, files: $0.2) })
        return PRRow(pr: pr, level: .notify, tier: tier, workSeconds: nil, workSecondsToNextTier: nil,
                     snoozedUntil: nil, computedAt: now)
    }
}
