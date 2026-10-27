import Foundation

/// Decides which banners and reminders to post. Precedence (first match wins): Hidden rule → hidden until
/// re-requested → Silent rule → snoozed → Notify.
enum NotificationPlanner {
    /// New-request banners for a snapshot. A banner fires when a key is unseen and either the PR wasn't waiting in
    /// the previous complete snapshot or its event is newer than that snapshot. Otherwise the key changed within
    /// the same episode and its state migrates silently. The first complete snapshot only seeds.
    static func ingest(_ snapshot: SyncSnapshot, _ state: inout RequestState, settings: NudgeSettings,
                       calendar: Calendar = .current) -> [PlannedNotification] {
        guard state.seeded else {
            guard snapshot.isComplete else { return [] }
            for pr in snapshot.prs {
                state.seen.insert(pr.requestKey)
                if tier(pr, at: snapshot.fetchedAt, settings, calendar) == .red { state.redNudged.insert(pr.requestKey) }
            }
            state.seeded = true
            state.recordComplete(snapshot)
            return []
        }
        var planned: [PlannedNotification] = []
        for pr in snapshot.prs where !state.seen.contains(pr.requestKey) {
            if let previous = state.previous, let old = previous.keysByPR[pr.prID],
               pr.requestedAt.map({ $0 <= previous.fetchedAt }) ?? true {
                state.migrate(from: old, to: pr.requestKey)
                continue
            }
            state.seen.insert(pr.requestKey)
            if RuleResolver.level(pr, settings) == .notify { planned.append(banner(pr)) }
        }
        if snapshot.isComplete { state.recordComplete(snapshot) }
        return planned
    }

    /// Expires snoozes and plans red reminders; runs after every snapshot and on the minute tick. Reminders wait
    /// while snoozed, stale, or off hours; Silent and Hidden consume them.
    static func tick(_ prs: [WaitingPR], _ state: inout RequestState, settings: NudgeSettings, now: Date,
                     isStale: Bool, calendar: Calendar = .current) -> [PlannedNotification] {
        state.snoozes = state.snoozes.filter { $0.value > now }
        guard state.seeded else { return [] }
        let working = WorkTime.isWorking(at: now, config: settings.workHours, calendar: calendar)
        var planned: [PlannedNotification] = []
        for pr in prs where !state.redNudged.contains(pr.requestKey) && tier(pr, at: now, settings, calendar) == .red {
            if RuleResolver.level(pr, settings) != .notify || state.hidden.contains(pr.requestKey) {
                state.redNudged.insert(pr.requestKey)
            } else if state.snoozes[pr.requestKey] == nil, !isStale, working {
                state.redNudged.insert(pr.requestKey)
                planned.append(reminder(pr, settings.thresholds))
            }
        }
        return planned
    }

    static func tier(_ pr: WaitingPR, at now: Date, _ settings: NudgeSettings, _ calendar: Calendar) -> Tier? {
        pr.waitingSince.map {
            TierPolicy.tier(workSeconds: WorkTime.elapsed(from: $0, to: now, config: settings.workHours, calendar: calendar),
                            settings.thresholds)
        }
    }

    static func banner(_ pr: WaitingPR) -> PlannedNotification {
        let title = switch (pr.requestedBy, pr.via) {
        case (nil, _): "Review requested"
        case let (actor?, .direct): "\(actor) requested your review"
        case let (actor?, .team): "\(actor) requested \(pr.via.label)'s review"
        }
        return PlannedNotification(id: pr.requestKey, kind: .newRequest, title: title, body: body(pr),
                                   rowID: pr.requestKey, url: pr.url)
    }

    static func reminder(_ pr: WaitingPR, _ thresholds: TierThresholds) -> PlannedNotification {
        let hours = thresholds.redWorkHours
        let amount = hours == hours.rounded() ? "\(Int(hours))h" : DurationFormat.compact(hours * 3600)
        return PlannedNotification(id: pr.requestKey, kind: .redReminder,
                                   title: "Still waiting on you · \(amount) of work time", body: body(pr),
                                   rowID: pr.requestKey, url: pr.url)
    }

    static func problem(_ problem: SyncProblem) -> PlannedNotification {
        PlannedNotification(id: "sync-problem", kind: .authProblem, title: problem.message, body: problem.fix ?? "",
                            rowID: nil, url: nil)
    }

    private static func body(_ pr: WaitingPR) -> String { "\(pr.repo)#\(pr.number) · \(pr.title)" }
}
