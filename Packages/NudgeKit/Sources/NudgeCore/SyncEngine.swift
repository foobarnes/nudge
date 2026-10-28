import Foundation

struct SyncResult: Sendable {
    let snapshot: SyncSnapshot
    let viewer: String
    /// Orgs the viewer belongs to, from the team query.
    let orgs: [String]
    let capped: Bool
    /// A non-fatal problem, e.g. orgs hidden by SAML SSO.
    let notice: SyncProblem?
}

enum SyncUpdate: Sendable {
    case synced(SyncResult)
    case failed(SyncError)
}

/// Polls GitHub. Launch, wake, manual, and timer triggers coalesce into one in-flight sync plus at most one
/// follow-up; results carry a generation and stale generations are dropped.
actor SyncEngine {
    enum Trigger: Sendable { case launch, timer, wake, manual }

    static let interval: TimeInterval = 15
    static let backoff: [TimeInterval] = [60, 120, 300]
    static let manualCooldown: TimeInterval = 10
    static let teamCacheTTL: TimeInterval = 3600

    private let tokens: TokenProviding
    private let client: GitHubClient
    private let now: @Sendable () -> Date
    private let deliver: @Sendable (SyncUpdate) async -> Void

    private var inFlight = false
    private var followUp = false
    private var generation = 0
    private var deliveredGeneration = 0
    private var failures = 0
    private var blockedUntil: Date?
    private var lastManual: Date?
    private var teamCache: (login: String, teams: GitHubClient.Teams, fetchedAt: Date)?
    private var loop: Task<Void, Never>?

    init(tokens: TokenProviding, client: GitHubClient, now: @escaping @Sendable () -> Date = { Date() },
         deliver: @escaping @Sendable (SyncUpdate) async -> Void) {
        self.tokens = tokens; self.client = client; self.now = now; self.deliver = deliver
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.trigger(.launch)
            while !Task.isCancelled, let delay = await self?.nextDelay() {
                try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(3))
                guard !Task.isCancelled else { return }
                await self?.trigger(.timer)
            }
        }
    }

    /// Stops polling and discards any sync still in flight.
    func stop() {
        loop?.cancel()
        loop = nil
        generation += 1
        deliveredGeneration = generation
    }

    /// Runs a sync, or schedules one follow-up if a sync is in flight. Returns once the syncs it ran finish.
    func trigger(_ reason: Trigger) async {
        let now = now()
        if reason != .launch, let blockedUntil, now < blockedUntil { return }
        if reason == .manual {
            if let lastManual, now.timeIntervalSince(lastManual) < Self.manualCooldown { return }
            lastManual = now
        }
        guard !inFlight else { followUp = true; return }
        inFlight = true
        repeat {
            followUp = false
            await syncOnce()
        } while followUp
        inFlight = false
    }

    /// 15s normally; 60s → 2m → 5m after consecutive failures; never before a rate-limit reset.
    func nextDelay() -> TimeInterval {
        let base = failures == 0 ? Self.interval : Self.backoff[min(failures, Self.backoff.count) - 1]
        guard let blockedUntil else { return base }
        return max(base, blockedUntil.timeIntervalSince(now()))
    }

    private func syncOnce() async {
        generation += 1
        let mine = generation
        let update: SyncUpdate
        do {
            update = .synced(try await fetch())
            failures = 0
            blockedUntil = nil
        } catch {
            let error = error as? SyncError ?? .badResponse(String(describing: error))
            failures += 1
            if case let .rateLimited(until) = error { blockedUntil = until ?? now().addingTimeInterval(nextDelay()) }
            update = .failed(error)
        }
        guard mine > deliveredGeneration else { return }
        deliveredGeneration = mine
        await deliver(update)
    }

    private func fetch() async throws -> SyncResult {
        let hourly = teamCache.map { now().timeIntervalSince($0.fetchedAt) >= Self.teamCacheTTL } ?? false
        do {
            return try await fetch(token: tokens.token(refresh: hourly))
        } catch SyncError.unauthorized {
            do {
                return try await fetch(token: tokens.token(refresh: true))
            } catch SyncError.unauthorized {
                throw SyncError.notLoggedIn
            }
        }
    }

    private func fetch(token: String) async throws -> SyncResult {
        let startedAt = now()
        let waiting = try await client.fetchWaiting(token: token)
        let teams = try await teams(for: waiting.viewer, token: token)
        let prs = ReviewRequestResolver.resolve(nodes: waiting.nodes, viewer: waiting.viewer, teams: teams.teams)
        return SyncResult(snapshot: SyncSnapshot(prs: prs, isComplete: waiting.isComplete, fetchedAt: startedAt),
                          viewer: waiting.viewer, orgs: teams.orgs, capped: waiting.capped, notice: waiting.sso)
    }

    /// Hourly, and immediately when the viewer changes (a `gh` account switch).
    private func teams(for login: String, token: String) async throws -> GitHubClient.Teams {
        let cached = teamCache?.login == login ? teamCache : nil
        if let cached, now().timeIntervalSince(cached.fetchedAt) < Self.teamCacheTTL { return cached.teams }
        do {
            let teams = try await client.fetchTeams(token: token, login: login)
            teamCache = (login, teams, now())
            return teams
        } catch let error as SyncError {
            switch error {
            case .offline, .badResponse: if let cached { return cached.teams }
            default: break
            }
            throw error
        }
    }
}
