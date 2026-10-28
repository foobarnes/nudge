import Foundation

/// Drives `NudgeState` from sync results, the minute tick, and user intents.
@MainActor
final class NudgeController: NudgeEngine {
    enum Source {
        case github(TokenProviding, GitHubClient)
        /// DEBUG fixture mode: a JSON file of synthetic requests stands in for GitHub.
        case fixture(URL)
    }

    static let fixtureViewer = "octocat"

    let state: NudgeState
    var onNotify: ((PlannedNotification) -> Void)?

    private let store: Store
    private let source: Source
    private let now: @MainActor () -> Date
    private let fixedCalendar: Calendar?
    private var engine: SyncEngine?
    private var tickTask: Task<Void, Never>?
    private var login: String?
    private var requests = RequestState()
    private var prs: [WaitingPR] = []
    private var viewerOrgs: [String] = []
    private var lastSync: Date?
    private var fixtureSnapshot: [WaitingPR]?
    private var problemNotified = false

    /// `calendar` pins a time zone for tests; otherwise the current system calendar is read on every use.
    init(state: NudgeState, store: Store, source: Source, now: @escaping @MainActor () -> Date = { Date() },
         calendar: Calendar? = nil) {
        self.state = state; self.store = store; self.source = source; self.now = now; self.fixedCalendar = calendar
        state.settings = store.loadSettings()
    }

    private var calendar: Calendar { fixedCalendar ?? .current }
    private var isStale: Bool { if case .stale = state.status { true } else { false } }

    // MARK: NudgeEngine

    func start() {
        switch source {
        case let .fixture(url):
            loadFixture(url)
        case let .github(tokens, client):
            guard engine == nil else { return }
            let engine = SyncEngine(tokens: tokens, client: client) { [weak self] update in await self?.apply(update) }
            self.engine = engine
            Task { await engine.start() }
        }
        startTicking()
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        if let engine { Task { await engine.stop() } }
        engine = nil
    }

    func syncNow() {
        if let engine { Task { await engine.trigger(.manual) } }
        if let fixtureSnapshot { applyFixture(fixtureSnapshot) }
    }

    func handleWake() {
        if let engine { Task { await engine.trigger(.wake) } }
        tick()
    }

    func snooze(_ row: PRRow, _ option: SnoozeOption) {
        guard let until = SnoozeParser.resolve(option, now: now(), config: state.settings.workHours, calendar: calendar)
        else { return }
        requests.snoozes[row.id] = until
        saveRequests()
        rebuild()
    }

    func unsnooze(_ row: PRRow) {
        requests.snoozes[row.id] = nil
        saveRequests()
        tick()
    }

    func hide(_ row: PRRow) {
        requests.hidden.insert(row.id)
        saveRequests()
        rebuild()
    }

    func updateSettings(_ change: (inout NudgeSettings) -> Void) {
        change(&state.settings)
        store.save(state.settings)
        tick()
    }

    func row(withID rowID: String) -> PRRow? {
        state.rows.first { $0.id == rowID } ?? state.snoozedRows.first { $0.id == rowID }
    }

    // MARK: Sync results

    func apply(_ update: SyncUpdate) {
        switch update {
        case let .synced(result):
            if login != result.viewer { switchAccount(to: result.viewer) }
            prs = result.snapshot.prs
            viewerOrgs = result.orgs
            lastSync = result.snapshot.fetchedAt
            problemNotified = false
            state.status = .ok(lastSync: result.snapshot.fetchedAt)
            state.resultsCapped = result.capped
            state.notice = result.notice
            let banners = NotificationPlanner.ingest(result.snapshot, &requests, settings: state.settings,
                                                     calendar: calendar)
            saveRequests()
            post(banners)
            tick()
        case let .failed(error):
            state.status = .stale(lastSync: lastSync, problem: error.problem)
            if error == .notLoggedIn, !problemNotified {
                problemNotified = true
                post([NotificationPlanner.problem(error.problem)])
            }
            rebuild()
        }
    }

    private func switchAccount(to viewer: String) {
        if let login { store.save(requests, login: login) }
        login = viewer
        requests = store.loadState(login: viewer)
    }

    private func loadFixture(_ url: URL) {
        do {
            let prs = try FixtureLoader.load(url, now: now())
            fixtureSnapshot = prs
            applyFixture(prs)
        } catch {
            apply(.failed(.badResponse("fixture: \(error.localizedDescription)")))
        }
    }

    private func applyFixture(_ prs: [WaitingPR]) {
        let snapshot = SyncSnapshot(prs: prs, isComplete: true, fetchedAt: now())
        apply(.synced(SyncResult(snapshot: snapshot, viewer: Self.fixtureViewer, orgs: [], capped: false, notice: nil)))
    }

    // MARK: Tick and rows

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = Date().timeIntervalSince1970
                let untilNextMinute = (seconds / 60).rounded(.down) * 60 + 60 - seconds
                try? await Task.sleep(for: .seconds(untilNextMinute), tolerance: .seconds(1))
                self?.tick()
            }
        }
    }

    /// Expires snoozes, plans red reminders, and recomputes tiers.
    func tick() {
        let before = requests
        let planned = NotificationPlanner.tick(prs, &requests, settings: state.settings, now: now(), isStale: isStale,
                                               calendar: calendar)
        if requests != before { saveRequests() }
        post(planned)
        rebuild()
    }

    private func post(_ planned: [PlannedNotification]) {
        for notification in planned {
            if notification.kind == .newRequest { state.newRequestPulse += 1 }
            onNotify?(notification)
        }
    }

    private func saveRequests() {
        if let login { store.save(requests, login: login) }
    }

    private func rebuild() {
        let now = now(), settings = state.settings
        var visible: [PRRow] = [], snoozed: [PRRow] = []
        for pr in prs {
            let level = RuleResolver.level(pr, settings)
            guard level != .hidden, !requests.hidden.contains(pr.requestKey) else { continue }
            let work = pr.waitingSince.map {
                WorkTime.elapsed(from: $0, to: now, config: settings.workHours, calendar: calendar)
            }
            let row = PRRow(
                pr: pr, level: level, tier: work.map { TierPolicy.tier(workSeconds: $0, settings.thresholds) } ?? .fresh,
                workSeconds: work, workSecondsToNextTier: work.flatMap {
                    TierPolicy.secondsToNextTier(workSeconds: $0, settings.thresholds)
                },
                snoozedUntil: requests.snoozes[pr.requestKey].flatMap { $0 > now ? $0 : nil }, computedAt: now)
            if row.snoozedUntil == nil { visible.append(row) } else { snoozed.append(row) }
        }
        state.rows = visible.sorted(by: Self.oldestFirst)
        state.snoozedRows = snoozed.sorted(by: Self.oldestFirst)
        state.isOffHours = !settings.workHours.weekdays.isEmpty
            && !WorkTime.isWorking(at: now, config: settings.workHours, calendar: calendar)
        state.viewerLogin = login
        state.knownOrgs = knownOrgs()
    }

    private static func oldestFirst(_ a: PRRow, _ b: PRRow) -> Bool {
        switch (a.pr.waitingSince, b.pr.waitingSince) {
        case let (x?, y?): x < y
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): a.pr.repo == b.pr.repo ? a.pr.number < b.pr.number : a.pr.repo < b.pr.repo
        }
    }

    /// Viewer orgs, orgs seen in results, and the viewer's own login for personal repos.
    private func knownOrgs() -> [OrgSummary] {
        let counts = Dictionary(grouping: prs, by: \.owner).mapValues(\.count)
        let logins = Set(viewerOrgs).union(counts.keys).union(login.map { [$0] } ?? [])
        return logins.sorted { $0.lowercased() < $1.lowercased() }.map {
            OrgSummary(login: $0, isViewer: $0 == login, waitingCount: counts[$0] ?? 0)
        }
    }
}

@MainActor
func _makeEngine(_ state: NudgeState, _ fixtureURL: URL?) -> NudgeEngine {
    let source: NudgeController.Source = fixtureURL.map { .fixture($0) }
        ?? .github(GhTokenProvider(), GitHubClient(transport: URLSessionTransport()))
    return NudgeController(state: state, store: Store(defaults: .standard), source: source)
}
