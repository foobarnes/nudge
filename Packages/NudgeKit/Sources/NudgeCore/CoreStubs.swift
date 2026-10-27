import Foundation

// Placeholder engine so NudgeUI and the shell compile while NudgeCore is built in parallel.

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
