import Foundation

enum TierPolicy {
    static func tier(workSeconds: TimeInterval, _ thresholds: TierThresholds) -> Tier {
        if workSeconds >= thresholds.redWorkHours * 3600 { return .red }
        if workSeconds >= thresholds.amberWorkHours * 3600 { return .amber }
        return .fresh
    }

    /// Work seconds left until the next tier; nil at Red.
    static func secondsToNextTier(workSeconds: TimeInterval, _ thresholds: TierThresholds) -> TimeInterval? {
        switch tier(workSeconds: workSeconds, thresholds) {
        case .fresh: thresholds.amberWorkHours * 3600 - workSeconds
        case .amber: thresholds.redWorkHours * 3600 - workSeconds
        case .red: nil
        }
    }
}

enum RuleResolver {
    /// Repo rule overrides org rule; default Notify. Matching ignores case, like GitHub logins.
    static func level(repo: String, orgRules: [String: NotifyLevel], repoRules: [String: NotifyLevel]) -> NotifyLevel {
        let repo = repo.lowercased()
        let org = String(repo.split(separator: "/").first ?? "")
        if let level = repoRules.first(where: { $0.key.lowercased() == repo })?.value { return level }
        if let level = orgRules.first(where: { $0.key.lowercased() == org })?.value { return level }
        return .notify
    }

    static func level(_ pr: WaitingPR, _ settings: NudgeSettings) -> NotifyLevel {
        level(repo: pr.repo, orgRules: settings.orgRules, repoRules: settings.repoRules)
    }
}
