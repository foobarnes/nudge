import AppKit
import NudgeCore

/// Menu bar glyph + waiting count. Left-click toggles the dropdown; right-click / control-click shows a menu. The open state is drawn by the dropdown itself,
/// not `button.highlight`, which regresses on macOS 27.
@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let state: NudgeState
    private let intents: NudgeIntents
    private let pill: PillController
    private let onClick: @MainActor () -> Void
    private var minuteTimer: Timer?

    init(state: NudgeState, intents: NudgeIntents, pill: PillController, onClick: @escaping @MainActor () -> Void) {
        self.state = state
        self.intents = intents
        self.pill = pill
        self.onClick = onClick
        guard let button = item.button else { return }
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])

        observeChanges({ [state] in Appearance(count: state.rows.count, isStale: state.status.isStale) }) { [weak self] in
            self?.render($0)
        }
        // Belt and braces: the count only changes with the rows, but re-render on the minute like the spec says.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.render(Appearance(count: self.state.rows.count, isStale: self.state.status.isStale))
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }

    /// The status item's screen: the display whose menu bar the user is looking at.
    var screen: NSScreen? { item.button?.window?.screen }

    /// The button's frame in screen coordinates.
    var buttonFrame: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true { showMenu() } else { onClick() }
    }

    // MARK: Context menu

    private func showMenu() {
        guard let button = item.button else { return }
        let menu = NSMenu()
        menu.addItem(MenuAction("Open List") { [intents] in intents.openDropdown() })
        if pill.isShown {
            menu.addItem(MenuAction("Hide Pill") { [intents] in intents.dismissPill() })
        } else {
            let show = MenuAction("Show Pill") { [pill] in pill.undismiss() }
            show.isEnabled = pill.dismissed && pill.wouldShow
            menu.addItem(show)
        }
        let modes = NSMenu()
        for (mode, title) in [(DisplayMode.menuBarOnly, "Menu Bar Only"), (.widgetAlways, "Widget"), (.auto, "Auto")] {
            let item = MenuAction(title) { [intents] in intents.updateSettings { $0.displayMode = mode } }
            item.state = state.settings.displayMode == mode ? .on : .off
            modes.addItem(item)
        }
        let timers = NSMenuItem(title: "Show Timers", action: nil, keyEquivalent: "")
        timers.submenu = modes
        menu.addItem(timers)
        menu.addItem(MenuAction("Sync Now") { [intents] in intents.syncNow() })
        menu.addItem(.separator())
        menu.addItem(MenuAction("Settings…", key: ",") { [intents] in intents.openSettings() })
        menu.addItem(MenuAction("Quit Nudge", key: "q") { [intents] in intents.quit() })
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private struct Appearance: Equatable, Sendable {
        var count: Int
        var isStale: Bool
    }

    private func render(_ a: Appearance) {
        guard let button = item.button else { return }
        let symbol = a.isStale ? "clock.badge.exclamationmark" : "clock.badge"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "clock.badge", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.title = a.count > 0 ? "\(a.count)" : ""
        let waiting = a.count == 1 ? "1 review waiting" : "\(a.count) reviews waiting"
        button.setAccessibilityLabel("Nudge, \(waiting)\(a.isStale ? ", sync problem" : "")")
    }
}

extension SyncStatus {
    var isStale: Bool { if case .stale = self { true } else { false } }
}

/// A menu item that runs a closure.
@MainActor
final class MenuAction: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
