import AppKit
import NudgeCore
import NudgeUI
import SwiftUI

/// Glass panel anchored under the status item. Key while open (keyboard navigation) without activating the app;
/// closes on Esc, a click elsewhere, losing key, or another status item click.
@MainActor
final class DropdownPanel: NSObject, NSWindowDelegate {
    private static let margin: CGFloat = 16      // transparent room around the content for the glass shadow
    private static let gap: CGFloat = 4          // between the menu bar and the panel's visible top

    private let panel: KeyPanel
    private var anchor: NSRect = .zero
    private var screen: NSScreen?
    private var contentSize: CGSize = .zero
    private var monitors: [Any] = []
    private var closedAt = Date.distantPast

    init(state: NudgeState, intents: NudgeIntents) {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        super.init()
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }
        panel.setAccessibilityLabel("Nudge reviews")

        let root = MeasuredContent(alignment: .top, margin: Self.margin, onSize: { [weak self] in self?.resize(to: $0) }) {
            DropdownView(state: state, intents: intents)
        }
        panel.contentView = makeHostingView(root)
    }

    var isShown: Bool { panel.isVisible }

    func show(below anchor: NSRect, on screen: NSScreen?) {
        // A click on the status item that also made the panel resign key shouldn't immediately reopen it.
        guard Date().timeIntervalSince(closedAt) > 0.25 else { return }
        self.anchor = anchor
        self.screen = screen
        panel.contentView?.layoutSubtreeIfNeeded()
        position()
        panel.makeKeyAndOrderFront(nil)    // non-activating: becomes key, the frontmost app stays active
        installMonitors()
    }

    func close() {
        guard panel.isVisible else { return }
        closedAt = Date()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.orderOut(nil)
    }

    /// Losing key to one of the panel's own popovers (row hover cards) doesn't count as leaving.
    func windowDidResignKey(_ notification: Notification) {
        after(0) { [weak self] in
            guard let self, !self.isOwn(NSApp.keyWindow) else { return }
            self.close()
        }
    }

    private func isOwn(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === panel || window.parent === panel
    }

    private func resize(to size: CGSize) {
        contentSize = size
        if panel.isVisible { position() }
    }

    private func position() {
        let m = Self.margin
        let size = NSSize(width: max(contentSize.width, 1) + 2 * m, height: max(contentSize.height, 1) + 2 * m)
        let visible = (screen ?? panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8 - m), visible.maxX - 8 + m - size.width)
        let top = min(anchor.minY, visible.maxY) - Self.gap + m
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        // Clicks in other apps.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { self.close() }
        }) { monitors.append(global) }
        // Clicks in Nudge's other windows (the pill, Settings). Status item clicks toggle through their own action.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
            MainActor.assumeIsolated {
                if !self.isOwn(event.window), event.window?.className.contains("StatusBar") != true { self.close() }
            }
            return event
        }) { monitors.append(local) }
    }
}

/// Borderless non-activating panel that may become key (for keyboard navigation) and forwards Esc.
final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
