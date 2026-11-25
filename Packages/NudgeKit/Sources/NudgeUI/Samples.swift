import Foundation
import NudgeCore
import SwiftUI

/// The sample PR the Actions editor renders its preview against. Synthetic, never real data.
public enum ActionPreview {
    public static let pr = WaitingPR(
        prID: "PR_b", repo: "acme/api", number: 4211, title: "Fix token refresh race",
        url: URL(string: "https://github.com/acme/api/pull/4211")!, author: "bo", headRef: "fix-refresh",
        via: .direct, requestedBy: "bo", requestKey: "RRE_b", requestedAt: nil, waitingSince: nil)
}

#if DEBUG
// Synthetic data for previews and the gallery. Mirrors the mockups: acme/*, alice/bo/carmen.

public enum SampleScenario: String, CaseIterable, Sendable {
    case mixed, fresh, amber, red, teamOnly, offHours, stale, authError, empty, loading, snoozed, notice
}

public extension NudgeState {
    static func sample(_ scenario: SampleScenario = .mixed, now: Date = .now) -> NudgeState {
        let state = NudgeState()
        let rows = SampleRows.all(now: now)
        state.status = .ok(lastSync: now.addingTimeInterval(-20))
        state.viewerLogin = "octocat"
        state.knownOrgs = [
            OrgSummary(login: "acme", isViewer: false, waitingCount: 3),
            OrgSummary(login: "widgets-inc", isViewer: false, waitingCount: 1),
            OrgSummary(login: "octocat", isViewer: true, waitingCount: 0),
        ]
        state.settings.orgRules = ["acme": .notify, "widgets-inc": .notify, "octocat": .silent]
        state.settings.repoRules = ["acme/infra": .silent, "acme/docs": .hidden]
        state.settings.actions = SampleRows.actions
        state.updates = UpdateStatus(lastChecked: now.addingTimeInterval(-25 * 60))

        switch scenario {
        case .mixed: state.rows = rows
        case .fresh: state.rows = [rows[2], rows[3]]
        case .amber: state.rows = [rows[1], rows[2], rows[3]]
        case .red: state.rows = rows
        case .teamOnly: state.rows = [rows[3]]
        case .offHours:
            state.rows = [rows[1], rows[2], rows[3]]
            state.isOffHours = true
        case .stale:
            state.rows = rows
            state.status = .stale(lastSync: now.addingTimeInterval(-12 * 60),
                                  problem: SyncProblem(message: "GitHub is unreachable.", fix: nil))
        case .authError:
            state.rows = []
            state.status = .stale(lastSync: now.addingTimeInterval(-12 * 60),
                                  problem: SyncProblem(message: "Your gh login expired.", fix: "Run gh auth login"))
        case .empty: state.rows = []
        case .loading:
            state.rows = []
            state.status = .starting
        case .snoozed:
            state.rows = [rows[0], rows[2], rows[3]]
            state.snoozedRows = [SampleRows.snoozed(rows[1], until: now.addingTimeInterval(3600))]
        case .notice:
            state.rows = rows
            state.notice = SyncProblem(message: "Authorize SSO for acme", fix: "gh auth refresh")
        }
        return state
    }
}

public enum SampleRows {
    public static func all(now: Date) -> [PRRow] {
        [
            row(now: now, id: "PR_a", repo: "acme/api", number: 4188, title: "API-212: Rate-limit retries for webhooks",
                author: "alice", branch: "retry-webhooks", waiting: 93_852, work: 9 * 3600 + 12 * 60, tier: .red,
                toNext: nil, diff: DiffStat(additions: 128, deletions: 42, files: 6)),
            row(now: now, id: "PR_b", repo: "acme/api", number: 4211, title: "Fix token refresh race",
                author: "bo", branch: "fix-refresh", waiting: 18_190, work: 5 * 3600 + 3 * 60, tier: .amber,
                toNext: 2 * 3600 + 57 * 60, diff: DiffStat(additions: 14, deletions: 3, files: 2)),
            row(now: now, id: "PR_c", repo: "acme/web", number: 930, title: "Export reports to CSV",
                author: "carmen", branch: "csv-export", waiting: 3803, work: 2 * 3600 + 48 * 60, tier: .fresh,
                toNext: 1 * 3600 + 12 * 60, diff: DiffStat(additions: 412, deletions: 37, files: 11)),
            row(now: now, id: "PR_d", repo: "acme/infra", number: 88, title: "Bump build dependencies",
                author: "dependabot", branch: "deps", waiting: 1270, work: 1270, tier: .fresh,
                toNext: 4 * 3600 - 1270, via: .team(org: "acme", slug: "backend"),
                diff: DiffStat(additions: 6, deletions: 6, files: 1)),
        ]
    }

    /// A two-line title for the hover card.
    public static func longTitle(now: Date) -> PRRow {
        row(now: now, id: "PR_e", repo: "acme/api", number: 4302,
            title: "Migrate the webhook delivery queue to the new retry scheduler and drop the legacy cron fallback",
            author: "alice", branch: "webhook-retry-scheduler", waiting: 41_000, work: 6 * 3600 + 20 * 60, tier: .amber,
            toNext: 1 * 3600 + 40 * 60, diff: DiffStat(additions: 640, deletions: 1_212, files: 23))
    }

    /// A two-line title and a branch that wraps: the tallest hover card.
    public static func longBranch(now: Date, tier: Tier) -> PRRow {
        row(now: now, id: "PR_g", repo: "acme/web", number: 512,
            title: "Pause the nightly export while a schema migration runs",
            author: "carmen", branch: "carmen/pause-nightly-export-during-schema-migrations", waiting: 73_260,
            work: 5 * 3600 + 21 * 60, tier: tier, toNext: 40 * 60)
    }

    public static func teamWithOthers(now: Date) -> PRRow {
        row(now: now, id: "PR_f", repo: "acme/infra", number: 91, title: "Rotate CI runner credentials",
            author: "carmen", branch: "rotate-runners", waiting: 5400, work: 5400, tier: .fresh, toNext: 4 * 3600 - 5400,
            via: .team(org: "acme", slug: "backend"), otherTeams: [.team(org: "acme", slug: "platform")])
    }

    public static let actions: [ReviewAction] = [
        ReviewAction(name: "Code review", symbol: "terminal", kind: .terminal,
                     template: "review-tool \"/review {url}\" --title {title}", repeatCount: 3, runOnStart: true),
        ReviewAction(name: "Open in diagram app", symbol: "rectangle.and.pencil.and.ellipsis", kind: .openURL,
                     template: "diagram://open?pr={url}", runOnStart: true),
        .viewDiff,
        ReviewAction(name: "Log to time tracker", symbol: "clock", kind: .background,
                     template: "track start \"{repo}#{number}\""),
    ]

    public static func snoozed(_ row: PRRow, until: Date) -> PRRow {
        PRRow(pr: row.pr, level: row.level, tier: row.tier, workSeconds: row.workSeconds,
              workSecondsToNextTier: row.workSecondsToNextTier, snoozedUntil: until, computedAt: row.computedAt)
    }

    private static func row(now: Date, id: String, repo: String, number: Int, title: String, author: String,
                            branch: String, waiting: TimeInterval, work: TimeInterval, tier: Tier,
                            toNext: TimeInterval?, via: RequestTarget = .direct, otherTeams: [RequestTarget] = [],
                            diff: DiffStat? = nil) -> PRRow {
        let since = now.addingTimeInterval(-waiting)
        let pr = WaitingPR(prID: id, repo: repo, number: number, title: title,
                           url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: author,
                           headRef: branch, via: via, otherTeams: otherTeams, requestedBy: author, requestKey: "\(id)#req",
                           requestedAt: since, waitingSince: since, diff: diff)
        return PRRow(pr: pr, level: .notify, tier: tier, workSeconds: work, workSecondsToNextTier: toNext,
                     snoozedUntil: nil, computedAt: now)
    }
}

/// Internal views exposed to the gallery so each can be screenshotted on its own.
public enum GalleryViews {
    @MainActor public static func workTimePopover(state: NudgeState) -> some View {
        WorkTimePopover(row: state.rows[2], config: state.settings.workHours, thresholds: state.settings.thresholds)
    }

    @MainActor public static func snoozeMenu(state: NudgeState, intents: NudgeIntents) -> some View {
        SnoozeMenu(row: state.rows[1], state: state, intents: intents) {}
    }

    @MainActor public static func hoverCard(_ row: PRRow, intents: NudgeIntents) -> some View {
        PRHoverCard(row: row, intents: intents)
    }

    @MainActor public static func row(_ row: PRRow, state: NudgeState, intents: NudgeIntents, revealed: Bool) -> some View {
        PRRowView(row: row, state: state, intents: intents, live: true, isActive: revealed)
    }

    /// A row whose hover card `cardOpen` opens instead of the pointer, presented as the app presents it (an
    /// `NSPopover`).
    @MainActor public static func row(_ row: PRRow, state: NudgeState, intents: NudgeIntents, cardEdge: Edge,
                                      cardOpen: Bool) -> some View {
        OpenCardRow(row: row, state: state, intents: intents, cardEdge: cardEdge, open: cardOpen)
    }
}

private struct OpenCardRow: View {
    let row: PRRow
    let state: NudgeState
    let intents: NudgeIntents
    let cardEdge: Edge
    let open: Bool
    @State private var cards = HoverCardCoordinator()

    var body: some View {
        PRRowView(row: row, state: state, intents: intents, live: true, isActive: true, cardEdge: cardEdge)
            .environment(\.hoverCards, cards)
            .onChange(of: open, initial: true) { _, open in cards.openID = open ? row.id : nil }
    }
}
#endif
