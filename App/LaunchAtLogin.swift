import AppKit
import NudgeCore
import ServiceManagement

/// Keeps `settings.launchAtLogin` equal to the real `SMAppService.mainApp` status: reflects it at launch, and
/// registers / unregisters when Settings flips the toggle. On failure the toggle snaps back and a banner says why.
@MainActor
final class LaunchAtLogin {
    private let state: NudgeState
    private let engine: NudgeEngine
    private let alerts: NotificationService
    private let service = SMAppService.mainApp

    init(state: NudgeState, engine: NudgeEngine, alerts: NotificationService) {
        self.state = state
        self.engine = engine
        self.alerts = alerts
    }

    private var isOn: Bool { service.status == .enabled || service.status == .requiresApproval }

    func start() {
        reflect()
        // Skip the initial value: it may predate `reflect()` if the engine applies settings asynchronously.
        var initial = true
        observeChanges({ [state] in state.settings.launchAtLogin }) { [weak self] wanted in
            if initial { initial = false } else { self?.apply(wanted) }
        }
    }

    private func reflect() {
        let actual = isOn
        if state.settings.launchAtLogin != actual { engine.updateSettings { $0.launchAtLogin = actual } }
    }

    private func apply(_ wanted: Bool) {
        guard wanted != isOn else { return }
        do {
            if wanted { try service.register() } else { try service.unregister() }
            if service.status == .requiresApproval {
                alerts.alert(title: "Approve Nudge in Login Items",
                             body: "System Settings › General › Login Items needs your OK before Nudge opens at login.")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            alerts.alert(title: wanted ? "Couldn't turn on Launch at login" : "Couldn't turn off Launch at login",
                         body: error.localizedDescription)
        }
        reflect()
    }
}
