import AppKit
import NudgeCore
import NudgeUI
import SwiftUI

/// Frameless-looking tinted-glass Settings window. While it is open Nudge takes the `.regular` policy (Dock icon,
/// menu bar, normal activation); closing it returns to `.accessory`.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let cornerRadius: CGFloat = 30
    private let window: NSWindow

    init(state: NudgeState, intents: NudgeIntents) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        super.init()
        window.title = "Nudge Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // An empty unified toolbar gives the titlebar its taller height, which insets the traffic lights from the
        // rounded corner into the sidebar's top band instead of straddling its edge.
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self

        // The window takes the SwiftUI view's size (and follows it if the view changes size).
        let controller = NSHostingController(rootView: SettingsRootView(state: state, intents: intents))
        controller.sizingOptions = [.preferredContentSize]
        controller.safeAreaRegions = []   // draw under the transparent titlebar; the traffic lights float on the glass
        window.contentViewController = controller
        // Round the content and the window's frame view; otherwise the system frame draws its own corners and edge.
        for view in [controller.view, controller.view.superview].compactMap(\.self) {
            view.wantsLayer = true
            view.layer?.cornerRadius = Self.cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)   // no focus ring on the first sidebar row until the user presses Tab
        window.orderFrontRegardless()   // visible even if the system declines the activation request
        NSApp.activate()
        window.invalidateShadow()
    }

    func windowWillClose(_ notification: Notification) {
        // Defer so the window finishes closing before the Dock icon goes away.
        after(0) { NSApp.setActivationPolicy(.accessory) }
    }

    func windowDidResize(_ notification: Notification) { window.invalidateShadow() }
}
