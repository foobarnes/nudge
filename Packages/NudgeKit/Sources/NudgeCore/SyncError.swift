import Foundation

enum SyncError: Error, Hashable, Sendable {
    case ghMissing
    case notLoggedIn
    /// HTTP 401; the engine re-reads the token once before reporting `.notLoggedIn`.
    case unauthorized
    case rateLimited(until: Date?)
    case insufficientScopes
    case offline
    case badResponse(String)

    var problem: SyncProblem {
        switch self {
        case .ghMissing:
            SyncProblem(message: "GitHub CLI not found.", fix: "Install GitHub CLI: brew install gh")
        case .notLoggedIn, .unauthorized:
            SyncProblem(message: "Not signed in to GitHub.", fix: "Run gh auth login")
        case let .rateLimited(until):
            SyncProblem(message: until.map { "Rate limited until \($0.formatted(date: .omitted, time: .shortened))" }
                ?? "Rate limited by GitHub.", fix: nil)
        case .insufficientScopes:
            SyncProblem(message: "Your gh login can't read team membership.", fix: "Run gh auth refresh -s read:org")
        case .offline:
            SyncProblem(message: "Can't reach GitHub.", fix: nil)
        case let .badResponse(detail):
            SyncProblem(message: "GitHub returned an unexpected response (\(detail)).", fix: nil)
        }
    }

    static func ssoProblem(org: String?) -> SyncProblem {
        SyncProblem(message: "Some results are hidden by SAML SSO.",
                    fix: org.map { "Authorize SSO for \($0): gh auth refresh" } ?? "Authorize SSO: gh auth refresh")
    }
}
