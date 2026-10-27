import AppKit
import NudgeCore
import NudgeUI

/// Composition root: one `NudgeState`, one engine, and the AppKit surfaces around them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = NudgeState()
    private var engine: NudgeEngine!
    private var notifications: NotificationService!
    private var actions: ActionRunner!
    private var statusItem: StatusItemController!
    private var dropdown: DropdownPanel!
    private var pill: PillController!
    private var settingsWindow: SettingsWindowController!
    private var launchAtLogin: LaunchAtLogin!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()

        let launch = LaunchOptions()
        engine = NudgeEngineFactory.make(state: state, fixtureURL: launch.fixtureURL)
        notifications = NotificationService(state: state)
        actions = ActionRunner(state: state, alerts: notifications)

        let engine = engine!
        let intents = NudgeIntents(
            open: { NSWorkspace.shared.open($0.pr.url) },
            startReview: { [actions] row, actionID in actions?.startReview(row, actionID: actionID) },
            snooze: { engine.snooze($0, $1) },
            unsnooze: { engine.unsnooze($0) },
            hide: { engine.hide($0) },
            syncNow: { engine.syncNow() },
            updateSettings: { engine.updateSettings($0) },
            openSettings: { [weak self] in self?.openSettings() },
            quit: { NSApp.terminate(nil) })

        notifications.connect(engine: engine, intents: intents)
        engine.onNotify = { [notifications] in notifications?.post($0) }

        dropdown = DropdownPanel(state: state, intents: intents)
        statusItem = StatusItemController(state: state) { [weak self] in self?.toggleDropdown() }
        pill = PillController(state: state, intents: intents) { [weak self] in self?.statusItem.screen }
        settingsWindow = SettingsWindowController(state: state, intents: intents)
        launchAtLogin = LaunchAtLogin(state: state, engine: engine, alerts: notifications)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.handleWake() }
        }

        engine.start()
        if let mode = launch.displayMode { state.settings.displayMode = mode }   // DEBUG only; not persisted
        launchAtLogin.start()
        pill.start()
        notifications.authorize()
        switch launch.open {
        case "dropdown": after(1.5) { [weak self] in self?.toggleDropdown() }
        case "settings": after(1.5) { [weak self] in self?.openSettings() }
        default: break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }

    @objc func openSettings() {
        dropdown.close()
        settingsWindow.show()
    }

    private func toggleDropdown() {
        if dropdown.isShown { dropdown.close() } else if let anchor = statusItem.buttonFrame {
            dropdown.show(below: anchor, on: statusItem.screen)
        }
    }
}

/// DEBUG launch arguments (`-NudgeFixture <path>`, `-NudgeDisplayMode <mode>`), read from the argument domain.
struct LaunchOptions {
    var fixtureURL: URL?
    var displayMode: DisplayMode?
    /// `-NudgeOpen dropdown|settings`: open that surface shortly after launch, for checks without a pointer.
    var open: String?

    init(defaults: UserDefaults = .standard) {
        #if DEBUG
        if let path = defaults.string(forKey: "NudgeFixture") { fixtureURL = URL(fileURLWithPath: path) }
        displayMode = defaults.string(forKey: "NudgeDisplayMode").flatMap(DisplayMode.init(rawValue:))
        open = defaults.string(forKey: "NudgeOpen")
        #endif
    }
}
