import Foundation
import Observation

// Shared contract between NudgeCore (logic), NudgeUI (views), and the App shell (AppKit).
// Change a type here only with a matching update to every consumer.

// MARK: - Domain

public enum RequestTarget: Hashable, Codable, Sendable {
    case direct
    case team(org: String, slug: String)

    public var isTeam: Bool { if case .team = self { true } else { false } }
    public var label: String {
        switch self {
        case .direct: "you"
        case let .team(org, slug): "\(org)/\(slug)"
        }
    }
}

public enum Tier: Int, Comparable, Codable, Sendable {
    case fresh, amber, red
    public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
}

public enum NotifyLevel: String, Codable, CaseIterable, Sendable { case notify, silent, hidden }

public enum DisplayMode: String, Codable, CaseIterable, Sendable { case menuBarOnly, widgetAlways, auto }

public enum TerminalApp: String, Codable, CaseIterable, Sendable { case ghostty, terminal }

/// A request that is currently waiting on the viewer, as resolved from GitHub.
public struct WaitingPR: Identifiable, Hashable, Sendable {
    public var id: String { requestKey }
    public let prID: String
    public let repo: String          // "acme/api"
    public let number: Int
    public let title: String
    public let url: URL
    public let author: String
    public let headRef: String
    public let via: RequestTarget
    public let otherTeams: [RequestTarget]
    public let requestedBy: String?
    public let requestKey: String
    public let requestedAt: Date?
    public let waitingSince: Date?

    public init(prID: String, repo: String, number: Int, title: String, url: URL, author: String, headRef: String,
                via: RequestTarget, otherTeams: [RequestTarget] = [], requestedBy: String?, requestKey: String,
                requestedAt: Date?, waitingSince: Date?) {
        self.prID = prID; self.repo = repo; self.number = number; self.title = title; self.url = url
        self.author = author; self.headRef = headRef; self.via = via; self.otherTeams = otherTeams
        self.requestedBy = requestedBy; self.requestKey = requestKey; self.requestedAt = requestedAt
        self.waitingSince = waitingSince
    }

    public var owner: String { String(repo.split(separator: "/").first ?? "") }
    public var name: String { String(repo.split(separator: "/").last ?? "") }
}

public struct SyncSnapshot: Sendable {
    public let prs: [WaitingPR]
    public let isComplete: Bool
    public let fetchedAt: Date
    public init(prs: [WaitingPR], isComplete: Bool, fetchedAt: Date) {
        self.prs = prs; self.isComplete = isComplete; self.fetchedAt = fetchedAt
    }
}

// MARK: - Settings

public struct WorkHoursConfig: Codable, Hashable, Sendable {
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday).
    public var weekdays: Set<Int>
    public var startMinute: Int      // minutes after midnight, e.g. 9*60
    public var endMinute: Int        // must be > startMinute
    public init(weekdays: Set<Int> = [2, 3, 4, 5, 6], startMinute: Int = 9 * 60, endMinute: Int = 18 * 60) {
        self.weekdays = weekdays; self.startMinute = startMinute; self.endMinute = endMinute
    }
}

public struct TierThresholds: Codable, Hashable, Sendable {
    public var amberWorkHours: Double
    public var redWorkHours: Double
    public init(amberWorkHours: Double = 4, redWorkHours: Double = 8) {
        self.amberWorkHours = amberWorkHours; self.redWorkHours = redWorkHours
    }
}

public enum SnoozeOption: Hashable, Codable, Sendable {
    case minutes(Int)
    case untilTomorrow        // next calendar day at work start
    case untilNextWorkDay     // next working day at work start
    case until(Date)          // from the Custom field
}

public struct ReviewAction: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case terminal, background, openURL }
    public var id: UUID
    public var name: String
    public var symbol: String
    public var kind: Kind
    public var template: String
    public var repeatCount: Int
    public var runOnStart: Bool
    public init(id: UUID = UUID(), name: String, symbol: String, kind: Kind, template: String,
                repeatCount: Int = 1, runOnStart: Bool = false) {
        self.id = id; self.name = name; self.symbol = symbol; self.kind = kind; self.template = template
        self.repeatCount = repeatCount; self.runOnStart = runOnStart
    }

    public static let viewDiff = ReviewAction(name: "View diff", symbol: "plus.forwardslash.minus", kind: .terminal,
                                              template: "gh pr diff {number} --repo {repo}")
}

public struct NudgeSettings: Codable, Hashable, Sendable {
    public var displayMode: DisplayMode = .auto
    public var launchAtLogin = false
    public var workHours = WorkHoursConfig()
    public var thresholds = TierThresholds()
    public var terminalApp: TerminalApp = .ghostty
    public var defaultSnooze: SnoozeOption = .minutes(60)
    public var lastCustomSnoozeText: String?
    public var orgRules: [String: NotifyLevel] = [:]
    public var repoRules: [String: NotifyLevel] = [:]
    public var actions: [ReviewAction] = [.viewDiff]
    public var allowedURLSchemes: [String] = []
    public init() {}
}

// MARK: - View-facing state

/// One row as the UI shows it. Built by NudgeCore from a WaitingPR plus settings and the current time.
public struct PRRow: Identifiable, Hashable, Sendable {
    public var id: String { pr.requestKey }
    public let pr: WaitingPR
    public let level: NotifyLevel
    public let tier: Tier
    /// Work seconds elapsed since `pr.waitingSince` at `computedAt`; nil when the start time is unknown.
    public let workSeconds: TimeInterval?
    /// Work seconds left until the next tier; nil at Red or when unknown.
    public let workSecondsToNextTier: TimeInterval?
    public let snoozedUntil: Date?
    public let computedAt: Date

    public init(pr: WaitingPR, level: NotifyLevel, tier: Tier, workSeconds: TimeInterval?,
                workSecondsToNextTier: TimeInterval?, snoozedUntil: Date?, computedAt: Date) {
        self.pr = pr; self.level = level; self.tier = tier; self.workSeconds = workSeconds
        self.workSecondsToNextTier = workSecondsToNextTier; self.snoozedUntil = snoozedUntil
        self.computedAt = computedAt
    }
}

public struct SyncProblem: Hashable, Sendable {
    public let message: String   // "Your gh login expired."
    public let fix: String?      // "Run gh auth login"
    public init(message: String, fix: String?) { self.message = message; self.fix = fix }
}

public enum SyncStatus: Hashable, Sendable {
    case starting
    case ok(lastSync: Date)
    case stale(lastSync: Date?, problem: SyncProblem)
}

public struct OrgSummary: Hashable, Identifiable, Sendable {
    public var id: String { login }
    public let login: String
    public let isViewer: Bool
    public let waitingCount: Int
    public init(login: String, isViewer: Bool, waitingCount: Int) {
        self.login = login; self.isViewer = isViewer; self.waitingCount = waitingCount
    }
}

/// What the in-app updater last reported, for Settings → About. The shell's Sparkle updater writes it.
public struct UpdateStatus: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case idle, checking, upToDate
        case available(version: String)
        case failed(message: String)
    }
    public var phase: Phase
    public var lastChecked: Date?
    /// Sparkle's own setting: check hourly, then download and install in the background.
    public var checksAutomatically: Bool
    public init(phase: Phase = .idle, lastChecked: Date? = nil, checksAutomatically: Bool = true) {
        self.phase = phase; self.lastChecked = lastChecked; self.checksAutomatically = checksAutomatically
    }
}

/// Window chrome the AppKit shell drives and the pill view reads.
public enum ScreenEdge: String, Codable, Sendable { case top, bottom, left, right }

/// Single source of truth the views observe. NudgeCore's controller writes it; the shell writes the pill fields.
@MainActor @Observable
public final class NudgeState {
    public var rows: [PRRow] = []              // visible, sorted oldest-first
    public var snoozedRows: [PRRow] = []
    public var status: SyncStatus = .starting
    public var isOffHours = false
    public var settings = NudgeSettings()
    public var knownOrgs: [OrgSummary] = []
    public var viewerLogin: String?
    /// Incremented once per new-request banner; views bounce on change.
    public var newRequestPulse = 0
    public var resultsCapped = false           // "200+ results — some may be missing"
    /// Non-fatal sync notice shown in the footer while rows still display, e.g. SAML SSO gaps.
    public var notice: SyncProblem?
    /// nil when the updater is off: local builds have no Sparkle key.
    public var updates: UpdateStatus?

    // Pill chrome (written by the shell).
    public var pillExpanded = false
    public var pillEdge: ScreenEdge = .top
    public var pillDimmed = false

    public init() {}

    public var oldest: PRRow? { rows.first }
}

/// What views can ask for. The shell assembles this from the controller plus AppKit-only behaviors.
public struct NudgeIntents {
    public var open: @MainActor (PRRow) -> Void
    /// nil runs every `runOnStart` action (or opens the PR when there are none).
    public var startReview: @MainActor (PRRow, ReviewAction.ID?) -> Void
    public var snooze: @MainActor (PRRow, SnoozeOption) -> Void
    public var unsnooze: @MainActor (PRRow) -> Void
    public var hide: @MainActor (PRRow) -> Void
    public var syncNow: @MainActor () -> Void
    public var updateSettings: @MainActor (_ change: (inout NudgeSettings) -> Void) -> Void
    public var openSettings: @MainActor () -> Void
    public var quit: @MainActor () -> Void
    /// Opens the menu bar dropdown (from the pill's context menu).
    public var openDropdown: @MainActor () -> Void = {}
    /// Hides the floating pill until the next new request (display mode is unchanged).
    public var dismissPill: @MainActor () -> Void = {}
    /// Checks the appcast quietly; the result lands in `NudgeState.updates`.
    public var checkForUpdates: @MainActor () -> Void = {}
    /// Opens the updater's own install prompt for the update `checkForUpdates` found.
    public var installUpdate: @MainActor () -> Void = {}
    public var setChecksForUpdatesAutomatically: @MainActor (Bool) -> Void = { _ in }

    public init(open: @escaping @MainActor (PRRow) -> Void = { _ in },
                startReview: @escaping @MainActor (PRRow, ReviewAction.ID?) -> Void = { _, _ in },
                snooze: @escaping @MainActor (PRRow, SnoozeOption) -> Void = { _, _ in },
                unsnooze: @escaping @MainActor (PRRow) -> Void = { _ in },
                hide: @escaping @MainActor (PRRow) -> Void = { _ in },
                syncNow: @escaping @MainActor () -> Void = {},
                updateSettings: @escaping @MainActor (_ change: (inout NudgeSettings) -> Void) -> Void = { _ in },
                openSettings: @escaping @MainActor () -> Void = {},
                quit: @escaping @MainActor () -> Void = {}) {
        self.open = open; self.startReview = startReview; self.snooze = snooze; self.unsnooze = unsnooze
        self.hide = hide; self.syncNow = syncNow; self.updateSettings = updateSettings
        self.openSettings = openSettings; self.quit = quit
    }
}

// MARK: - Notifications and actions (core plans, shell performs)

public struct PlannedNotification: Hashable, Sendable {
    public enum Kind: String, Sendable { case newRequest, redReminder, authProblem, actionFailed }
    public let id: String           // notification identifier (requestKey for request kinds)
    public let kind: Kind
    public let title: String        // "alice requested your review"
    public let body: String         // "acme/api #4211 · Fix token refresh"
    public let rowID: String?
    public let url: URL?
    public init(id: String, kind: Kind, title: String, body: String, rowID: String?, url: URL?) {
        self.id = id; self.kind = kind; self.title = title; self.body = body; self.rowID = rowID; self.url = url
    }
}

public enum RenderedAction: Hashable, Sendable {
    /// Full zsh script text: `emulate -R zsh`, escaped exports, the user's template, self-delete trap.
    case shell(script: String)
    case url(URL)
}

// MARK: - Core APIs the UI and shell call. NudgeCore owns the implementations.

public enum WorkTime {
    /// Working seconds between two instants under `config`.
    public static func elapsed(from: Date, to: Date, config: WorkHoursConfig, calendar: Calendar = .current) -> TimeInterval {
        _workTimeElapsed(from, to, config, calendar)
    }
    /// Working intervals inside [from, to], for the breakdown timeline.
    public static func segments(from: Date, to: Date, config: WorkHoursConfig, calendar: Calendar = .current) -> [DateInterval] {
        _workTimeSegments(from, to, config, calendar)
    }
    public static func isWorking(at date: Date, config: WorkHoursConfig, calendar: Calendar = .current) -> Bool {
        _workTimeIsWorking(date, config, calendar)
    }
    /// Start of the next working window strictly after `date`; nil with zero working days.
    public static func nextStart(after date: Date, config: WorkHoursConfig, calendar: Calendar = .current) -> Date? {
        _workTimeNextStart(date, config, calendar)
    }
}

public enum SnoozeParser {
    /// Parses "45m", "2h", "1h30m", "4pm", "16:30", "tomorrow", "mon" into an end date after `now`.
    public static func parse(_ text: String, now: Date, config: WorkHoursConfig, calendar: Calendar = .current) -> Date? {
        _snoozeParse(text, now, config, calendar)
    }
    public static func resolve(_ option: SnoozeOption, now: Date, config: WorkHoursConfig, calendar: Calendar = .current) -> Date? {
        _snoozeResolve(option, now, config, calendar)
    }
}

public enum ActionRendering {
    /// Renders an action for one PR. Throws `ActionTemplateError` for invalid templates (token in single quotes,
    /// token in URL scheme/host, disallowed scheme, unparseable URL).
    public static func render(_ action: ReviewAction, pr: WaitingPR, allowedSchemes: [String]) throws -> RenderedAction {
        try _renderAction(action, pr, allowedSchemes)
    }
    /// Human-readable problems for the Settings editor; empty when valid.
    public static func problems(template: String, kind: ReviewAction.Kind, allowedSchemes: [String]) -> [String] {
        _actionProblems(template, kind, allowedSchemes)
    }
}

public struct ActionTemplateError: Error, Hashable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

// MARK: - Engine (NudgeCore implements; the shell drives it)

@MainActor
public protocol NudgeEngine: AnyObject {
    /// Called for every banner the planner decides to post.
    var onNotify: ((PlannedNotification) -> Void)? { get set }
    func start()
    func stop()
    func syncNow()
    func handleWake()
    func snooze(_ row: PRRow, _ option: SnoozeOption)
    func unsnooze(_ row: PRRow)
    func hide(_ row: PRRow)
    func updateSettings(_ change: (inout NudgeSettings) -> Void)
    /// Records that the notification for `rowID` was acted on (e.g. snoozed from the banner).
    func row(withID rowID: String) -> PRRow?
}

public enum NudgeEngineFactory {
    /// `fixtureURL` (DEBUG `-NudgeFixture`) replaces GitHub with a JSON fixture of WaitingPRs.
    @MainActor public static func make(state: NudgeState, fixtureURL: URL? = nil) -> NudgeEngine {
        _makeEngine(state, fixtureURL)
    }
}
