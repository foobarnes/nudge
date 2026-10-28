import Foundation
@testable import NudgeCore
import Testing

/// Replays snapshot sequences (Acceptance Criteria 2, cases a–k). Times are New York, Tue 2026-01-06 unless noted.
@Suite struct NotificationPlannerTests {
    struct Replay {
        var state = RequestState()
        var settings = NudgeSettings()
        var stale = false

        /// Ingests a snapshot and runs the tick at its fetch time, like the controller.
        mutating func sync(_ prs: [WaitingPR], _ time: String, complete: Bool = true) -> [PlannedNotification] {
            let snapshot = SyncSnapshot(prs: prs, isComplete: complete, fetchedAt: at(time))
            return NotificationPlanner.ingest(snapshot, &state, settings: settings, calendar: newYork)
                + tick(prs, time)
        }

        mutating func tick(_ prs: [WaitingPR], _ time: String) -> [PlannedNotification] {
            NotificationPlanner.tick(prs, &state, settings: settings, now: at(time), isStale: stale, calendar: newYork)
        }
    }

    func banners(_ planned: [PlannedNotification]) -> Int { planned.filter { $0.kind == .newRequest }.count }
    func reminders(_ planned: [PlannedNotification]) -> Int { planned.filter { $0.kind == .redReminder }.count }

    let a = makePR(id: "PR_a", number: 1, key: "RRE_a", waitingSince: at("2026-01-05 10:00"))
    let b = makePR(id: "PR_b", number: 2, key: "RRE_b", waitingSince: at("2026-01-06 09:00"))

    @Test func a_firstLaunchBacklogIsSilent() {
        var r = Replay()
        let planned = r.sync([a, b], "2026-01-06 10:00")
        #expect(planned.isEmpty)
        #expect(r.state.redNudged == ["RRE_a"], "already-red requests are seeded as reminded")
        #expect(r.tick([a, b], "2026-01-06 10:30").isEmpty)
    }

    @Test func b_newKeyNotifiesOnce() {
        var r = Replay()
        _ = r.sync([a], "2026-01-06 10:00")
        let c = makePR(id: "PR_c", number: 3, key: "RRE_c", waitingSince: at("2026-01-06 10:00"))
        #expect(banners(r.sync([a, c], "2026-01-06 10:01")) == 1)
        #expect(banners(r.sync([a, c], "2026-01-06 10:02")) == 0)
    }

    @Test func c_relaunchDoesNotRenotify() throws {
        let suite = "nudge-tests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        var r = Replay()
        _ = r.sync([a], "2026-01-06 10:00")
        let c = makePR(id: "PR_c", number: 3, key: "RRE_c", waitingSince: at("2026-01-06 10:00"))
        #expect(banners(r.sync([a, c], "2026-01-06 10:01")) == 1)
        Store(defaults: try #require(UserDefaults(suiteName: suite))).save(r.state, login: "octocat")

        var relaunched = Replay()
        relaunched.state = Store(defaults: try #require(UserDefaults(suiteName: suite))).loadState(login: "octocat")
        #expect(relaunched.state == r.state)
        #expect(relaunched.sync([a, c], "2026-01-06 10:05").isEmpty)
    }

    @Test func d_reRequestNotifiesAgain() {
        var r = Replay()
        let first = makePR(key: "RRE_1", waitingSince: at("2026-01-06 09:00"))
        _ = r.sync([first], "2026-01-06 10:00")
        _ = r.sync([], "2026-01-06 10:30") // review submitted
        let again = makePR(key: "RRE_2", waitingSince: at("2026-01-06 10:45"))
        #expect(banners(r.sync([again], "2026-01-06 11:00")) == 1)
    }

    @Test func e_incompleteSnapshotKeepsState() {
        var r = Replay()
        _ = r.sync([b], "2026-01-06 10:00")
        r.state.hidden.insert("RRE_b")
        r.state.snoozes["RRE_b"] = at("2026-01-12 09:00")
        _ = r.sync([], "2026-01-07 11:00", complete: false) // > 24h later, PR missing from a partial result
        #expect(r.state.seen.contains("RRE_b"))
        let planned = r.sync([b], "2026-01-07 11:01")
        #expect(banners(planned) == 0)
        #expect(r.state.hidden.contains("RRE_b"))
        #expect(r.state.snoozes["RRE_b"] == at("2026-01-12 09:00"))
    }

    @Test func f_directRemovedTeamRemainsMigrates() {
        var r = Replay()
        let direct = makePR(key: "RRE_d", requestedAt: at("2026-01-06 09:30"), waitingSince: at("2026-01-06 09:30"))
        _ = r.sync([direct], "2026-01-06 10:00")
        r.state.snoozes["RRE_d"] = at("2026-01-06 15:00")
        let viaTeam = makePR(via: .team(org: "acme", slug: "backend"), key: "RRE_t",
                             waitingSince: at("2026-01-06 09:00"))
        #expect(banners(r.sync([viaTeam], "2026-01-06 10:01")) == 0)
        #expect(r.state.seen.contains("RRE_t"))
        #expect(r.state.snoozes["RRE_t"] == at("2026-01-06 15:00"))
    }

    @Test func g_draftBecomesReadyNotifies() {
        var r = Replay()
        _ = r.sync([a], "2026-01-06 10:00") // the draft is excluded from this snapshot
        let readied = makePR(id: "PR_g", key: "RRE_g", requestedAt: at("2026-01-06 08:00"),
                             waitingSince: at("2026-01-06 10:04"))
        #expect(banners(r.sync([a, readied], "2026-01-06 10:05")) == 1)
    }

    @Test func h_reRequestBetweenPollsNotifies() {
        var r = Replay()
        _ = r.sync([makePR(key: "RRE_1", waitingSince: at("2026-01-06 09:00"))], "2026-01-06 10:00")
        let reRequested = makePR(key: "RRE_2", waitingSince: at("2026-01-06 10:00:30"))
        #expect(banners(r.sync([reRequested], "2026-01-06 10:01")) == 1)
    }

    @Test func i_hiddenUnknownToKnownStaysHidden() {
        var r = Replay()
        _ = r.sync([makePR(requestedBy: nil, key: "PR_1#direct#unknown")], "2026-01-06 10:00")
        r.state.hidden.insert("PR_1#direct#unknown")
        let known = makePR(key: "RRE_a", waitingSince: at("2026-01-06 08:00"))
        #expect(r.sync([known], "2026-01-06 10:01").isEmpty)
        #expect(r.state.hidden.contains("RRE_a"))
    }

    @Test func j_silentSnoozedRedNeverReminds() {
        var r = Replay()
        r.settings.orgRules = ["acme": .silent]
        _ = r.sync([b], "2026-01-06 10:00")
        r.state.snoozes["RRE_b"] = at("2026-01-07 10:00")
        #expect(reminders(r.tick([b], "2026-01-06 17:30")) == 0) // crosses Red at 17:00
        #expect(reminders(r.tick([b], "2026-01-07 10:01")) == 0) // after snooze expiry
        #expect(r.state.snoozes.isEmpty)
    }

    @Test func k_freshAtLaunchRemindsExactlyOnceAtRed() {
        var r = Replay()
        _ = r.sync([b], "2026-01-06 10:00")
        #expect(reminders(r.tick([b], "2026-01-06 16:59")) == 0)
        let planned = r.tick([b], "2026-01-06 17:00")
        #expect(reminders(planned) == 1)
        #expect(planned.first?.title == "Still waiting on you · 8h of work time")
        #expect(planned.first?.body == "acme/api#2 · Fix token refresh")
        #expect(reminders(r.tick([b], "2026-01-06 17:30") + r.sync([b], "2026-01-07 10:00")) == 0)
    }

    @Test func snoozeDefersReminderToExpiry() {
        var r = Replay()
        _ = r.sync([b], "2026-01-06 10:00")
        r.state.snoozes["RRE_b"] = at("2026-01-06 17:30")
        #expect(reminders(r.tick([b], "2026-01-06 17:10")) == 0)
        #expect(reminders(r.tick([b], "2026-01-06 17:31")) == 1)
    }

    @Test func staleAndOffHoursDeferReminders() {
        var r = Replay()
        _ = r.sync([b], "2026-01-06 10:00")
        r.stale = true
        #expect(reminders(r.tick([b], "2026-01-06 17:10")) == 0)
        r.stale = false
        r.settings.thresholds = TierThresholds(amberWorkHours: 1, redWorkHours: 2)
        #expect(reminders(r.tick([b], "2026-01-06 19:00")) == 0, "off hours")
        #expect(reminders(r.tick([b], "2026-01-07 09:00")) == 1)
    }

    @Test func unknownTimeBannersButNeverReminds() {
        var r = Replay()
        _ = r.sync([], "2026-01-06 10:00")
        let unknown = makePR(key: "PR_1#direct#unknown")
        #expect(banners(r.sync([unknown], "2026-01-06 10:01")) == 1)
        #expect(reminders(r.tick([unknown], "2026-01-09 17:00")) == 0)
    }

    @Test func silentAndHiddenRulesSuppressBannersWithoutBackfill() {
        var r = Replay()
        _ = r.sync([], "2026-01-06 10:00")
        r.settings.orgRules = ["acme": .hidden]
        r.settings.repoRules = ["acme/web": .silent]
        let web = makePR(id: "PR_w", repo: "acme/web", key: "RRE_w", waitingSince: at("2026-01-06 10:00"))
        #expect(banners(r.sync([b, web], "2026-01-06 10:01")) == 0)
        r.settings.orgRules = [:]
        r.settings.repoRules = [:]
        #expect(banners(r.sync([b, web], "2026-01-06 10:02")) == 0)
    }

    @Test func incompleteFirstSyncWaitsForCompleteSeed() {
        var r = Replay()
        #expect(r.sync([a], "2026-01-06 10:00", complete: false).isEmpty)
        #expect(!r.state.seeded)
        #expect(r.sync([a, b], "2026-01-06 10:01").isEmpty)
        #expect(r.state.seeded)
    }

    @Test func prunesAfter24hOfCompleteAbsence() {
        var r = Replay()
        _ = r.sync([b], "2026-01-06 10:00")
        r.state.hidden.insert("RRE_b")
        _ = r.sync([], "2026-01-07 09:59")
        #expect(r.state.hidden.contains("RRE_b"))
        _ = r.sync([], "2026-01-07 10:00")
        #expect(!r.state.hidden.contains("RRE_b"))
        #expect(!r.state.seen.contains("RRE_b"))
    }

    @Test func wording() {
        #expect(NotificationPlanner.banner(makePR()).title == "alice requested your review")
        #expect(NotificationPlanner.banner(makePR()).body == "acme/api#4211 · Fix token refresh")
        #expect(NotificationPlanner.banner(makePR(via: .team(org: "acme", slug: "backend"), requestedBy: "bo")).title
            == "bo requested acme/backend's review")
        #expect(NotificationPlanner.banner(makePR(requestedBy: nil)).title == "Review requested")
        #expect(NotificationPlanner.reminder(makePR(), TierThresholds(amberWorkHours: 0.02, redWorkHours: 0.05)).title
            == "Still waiting on you · 3m of work time")
        let auth = NotificationPlanner.problem(SyncError.notLoggedIn.problem)
        #expect(auth.kind == .authProblem)
        #expect(auth.body == "Run gh auth login")
    }
}
