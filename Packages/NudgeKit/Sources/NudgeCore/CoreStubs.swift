import Foundation

// Placeholder bodies so NudgeUI and the shell compile while NudgeCore is built in parallel.
// The core implementation replaces this file (WorkTime.swift, SnoozeParser.swift).

func _workTimeElapsed(_ from: Date, _ to: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> TimeInterval {
    max(0, to.timeIntervalSince(from))
}

func _workTimeSegments(_ from: Date, _ to: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> [DateInterval] {
    to > from ? [DateInterval(start: from, end: to)] : []
}

func _workTimeIsWorking(_ date: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Bool { true }

func _workTimeNextStart(_ date: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    date.addingTimeInterval(3600)
}

func _snoozeParse(_ text: String, _ now: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? { nil }

func _snoozeResolve(_ option: SnoozeOption, _ now: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    switch option {
    case let .minutes(m): now.addingTimeInterval(TimeInterval(m * 60))
    case let .until(date): date
    case .untilTomorrow, .untilNextWorkDay: now.addingTimeInterval(16 * 3600)
    }
}

func _renderAction(_ action: ReviewAction, _ pr: WaitingPR, _ allowedSchemes: [String]) throws -> RenderedAction {
    .shell(script: "emulate -R zsh\n" + action.template)
}

func _actionProblems(_ template: String, _ kind: ReviewAction.Kind, _ allowedSchemes: [String]) -> [String] { [] }

@MainActor
private final class StubEngine: NudgeEngine {
    let state: NudgeState
    var onNotify: ((PlannedNotification) -> Void)?
    init(state: NudgeState) { self.state = state }
    func start() { state.status = .ok(lastSync: .now) }
    func stop() {}
    func syncNow() {}
    func handleWake() {}
    func snooze(_ row: PRRow, _ option: SnoozeOption) {}
    func unsnooze(_ row: PRRow) {}
    func hide(_ row: PRRow) {}
    func updateSettings(_ change: (inout NudgeSettings) -> Void) { change(&state.settings) }
    func row(withID rowID: String) -> PRRow? { state.rows.first { $0.id == rowID } }
}

@MainActor
func _makeEngine(_ state: NudgeState, _ fixtureURL: URL?) -> NudgeEngine { StubEngine(state: state) }
