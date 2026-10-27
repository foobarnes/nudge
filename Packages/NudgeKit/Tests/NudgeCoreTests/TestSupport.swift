import Foundation
@testable import NudgeCore

let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// "2026-01-09 17:00" in `calendar`'s time zone.
func at(_ text: String, _ calendar: Calendar = newYork) -> Date {
    let parts = text.split(whereSeparator: { "- :".contains($0) }).map { Int($0)! }
    let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])
    return calendar.date(from: components)!
}

func makePR(id: String = "PR_1", repo: String = "acme/api", number: Int = 4211, title: String = "Fix token refresh",
            via: RequestTarget = .direct, requestedBy: String? = "alice", key: String = "RRE_a",
            requestedAt: Date? = nil, waitingSince: Date? = nil) -> WaitingPR {
    WaitingPR(prID: id, repo: repo, number: number, title: title,
              url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: "alice", headRef: "fix-refresh",
              via: via, requestedBy: requestedBy, requestKey: key, requestedAt: requestedAt ?? waitingSince,
              waitingSince: waitingSince)
}

func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
}

func freshDefaults() -> UserDefaults {
    let name = "nudge-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
