import Foundation

/// Per-login request state. Keys are pruned only after complete snapshots have lacked them for 24h, so a PR that
/// drops out of an incomplete snapshot doesn't come back as new.
struct RequestState: Codable, Equatable, Sendable {
    struct Previous: Codable, Equatable, Sendable {
        var keysByPR: [String: String]
        var fetchedAt: Date
    }

    var seeded = false
    var seen: Set<String> = []
    var redNudged: Set<String> = []
    var hidden: Set<String> = []
    var snoozes: [String: Date] = [:]
    var lastPresent: [String: Date] = [:]
    /// The last complete snapshot, for episode detection.
    var previous: Previous?

    static let pruneAfter: TimeInterval = 24 * 3600

    /// Same-episode key change: carry every per-key flag from the old key to the new one.
    mutating func migrate(from old: String, to new: String) {
        seen.insert(new)
        if redNudged.contains(old) { redNudged.insert(new) }
        if hidden.contains(old) { hidden.insert(new) }
        if let until = snoozes[old] { snoozes[new] = until }
        lastPresent[new] = lastPresent[old]
    }

    mutating func recordComplete(_ snapshot: SyncSnapshot) {
        let now = snapshot.fetchedAt
        for pr in snapshot.prs { lastPresent[pr.requestKey] = now }
        let tracked = seen.union(redNudged).union(hidden).union(snoozes.keys).union(lastPresent.keys)
        for key in tracked {
            let last = lastPresent[key] ?? now
            if now.timeIntervalSince(last) >= Self.pruneAfter {
                seen.remove(key); redNudged.remove(key); hidden.remove(key)
                snoozes[key] = nil; lastPresent[key] = nil
            } else {
                lastPresent[key] = last
            }
        }
        previous = Previous(keysByPR: Dictionary(snapshot.prs.map { ($0.prID, $0.requestKey) }) { a, _ in a },
                            fetchedAt: now)
    }
}

/// UserDefaults persistence: settings are global, request state is namespaced `state.<login>.*`.
struct Store {
    let defaults: UserDefaults

    func loadSettings() -> NudgeSettings { load("settings") ?? NudgeSettings() }
    func save(_ settings: NudgeSettings) { save(settings, "settings") }

    func loadState(login: String) -> RequestState { load("state.\(login).requests") ?? RequestState() }
    func save(_ state: RequestState, login: String) { save(state, "state.\(login).requests") }

    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
