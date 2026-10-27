import AppKit
import NudgeCore

/// Menu bar glyph + waiting count. Click toggles the dropdown. The open state is drawn by the dropdown itself,
/// not `button.highlight`, which regresses on macOS 27.
@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let state: NudgeState
    private let onClick: @MainActor () -> Void
    private var minuteTimer: Timer?

    init(state: NudgeState, onClick: @escaping @MainActor () -> Void) {
        self.state = state
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

    @objc private func clicked() { onClick() }

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
