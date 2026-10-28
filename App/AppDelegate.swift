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
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()

        let launch = LaunchOptions()
        engine = NudgeEngineFactory.make(state: state, fixtureURL: launch.fixtureURL)
        notifications = NotificationService(state: state)
        actions = ActionRunner(state: state, alerts: notifications)

        let engine = engine!
        var intents = NudgeIntents(
            open: { NSWorkspace.shared.open($0.pr.url) },
            startReview: { [actions] row, actionID in actions?.startReview(row, actionID: actionID) },
            snooze: { engine.snooze($0, $1) },
            unsnooze: { engine.unsnooze($0) },
            hide: { engine.hide($0) },
            syncNow: { engine.syncNow() },
            updateSettings: { engine.updateSettings($0) },
            openSettings: { [weak self] in self?.openSettings() },
            quit: { NSApp.terminate(nil) })
        intents.openDropdown = { [weak self] in self?.showDropdown() }
        intents.dismissPill = { [weak self] in self?.pill.dismiss() }

        notifications.connect(engine: engine, intents: intents)
        engine.onNotify = { [notifications] in notifications?.post($0) }

        dropdown = DropdownPanel(state: state, intents: intents)
        pill = PillController(state: state, intents: intents) { [weak self] in self?.statusItem.screen }
        statusItem = StatusItemController(state: state, intents: intents, pill: pill, updater: updater) { [weak self] in
            self?.toggleDropdown()
        }
        settingsWindow = SettingsWindowController(state: state, intents: intents)
        launchAtLogin = LaunchAtLogin(state: state, engine: engine, alerts: notifications)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.handleWake() }
        }

        engine.start()
        if let mode = launch.displayMode { state.settings.displayMode = mode }   // DEBUG only; not persisted
        launchAtLogin.start()
        pill.contextMenu = { [weak self] in self?.statusItem.makeMenu() ?? NSMenu() }
        pill.start()
        notifications.authorize()
        switch launch.open {
        case "dropdown": after(1.5) { [weak self] in self?.toggleDropdown() }
        case "settings": after(1.5) { [weak self] in self?.openSettings() }
        default: break
        }
        if let seconds = launch.expandAfter {
            after(seconds) { [weak self] in self?.pill.setExpandedForTesting(true) }
        }
        if let interval = launch.snapEvery {
            Task { @MainActor [weak self] in
                for i in 0..<6 {
                    try? await Task.sleep(for: .seconds(interval))
                    guard let vf = self?.pill.screenForTesting?.visibleFrame else { return }
                    let x = i.isMultiple(of: 2) ? vf.minX + 120 : vf.maxX - 600
                    self?.pill.dropForTesting(at: NSPoint(x: x, y: vf.minY + 40))
                }
            }
        }
        if let interval = launch.toggleEvery {
            Task { @MainActor [weak self] in
                for i in 0..<20 {
                    try? await Task.sleep(for: .seconds(interval))
                    self?.pill.setExpandedForTesting(i.isMultiple(of: 2))
                }
            }
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
        if dropdown.isShown { dropdown.close() } else { showDropdown() }
    }

    private func showDropdown() {
        guard !dropdown.isShown, let anchor = statusItem.buttonFrame else { return }
        dropdown.show(below: anchor, on: statusItem.screen)
    }
}

/// DEBUG launch arguments (`-NudgeFixture <path>`, `-NudgeDisplayMode <mode>`), read from the argument domain.
struct LaunchOptions {
    var fixtureURL: URL?
    var displayMode: DisplayMode?
    /// `-NudgeOpen dropdown|settings`: open that surface shortly after launch, for checks without a pointer.
    var open: String?
    /// `-NudgeExpandAfter <seconds>`: expand the pill without hovering. `-NudgeToggleEvery <seconds>`: then
    /// toggle it 20 times, for hang and CPU checks.
    var expandAfter: Double?
    var toggleEvery: Double?
    /// `-NudgeSnapEvery <seconds>`: drop the pill mid-screen and let it snap, 6 times.
    var snapEvery: Double?

    init(defaults: UserDefaults = .standard) {
        #if DEBUG
        if let path = defaults.string(forKey: "NudgeFixture") { fixtureURL = URL(fileURLWithPath: path) }
        displayMode = defaults.string(forKey: "NudgeDisplayMode").flatMap(DisplayMode.init(rawValue:))
        open = defaults.string(forKey: "NudgeOpen")
        if defaults.object(forKey: "NudgeExpandAfter") != nil { expandAfter = defaults.double(forKey: "NudgeExpandAfter") }
        if defaults.object(forKey: "NudgeToggleEvery") != nil { toggleEvery = defaults.double(forKey: "NudgeToggleEvery") }
        if defaults.object(forKey: "NudgeSnapEvery") != nil { snapEvery = defaults.double(forKey: "NudgeSnapEvery") }
        #endif
    }
}
