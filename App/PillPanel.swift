import AppKit
import NudgeCore
import NudgeUI
import SwiftUI

/// Where the pill sits on one display: the content corner it grows away from, as fractions of the visible frame.
struct PillAnchor: Codable, Equatable {
    var trailing: Bool
    var top: Bool
    var fx: Double
    var fy: Double
    var edge: ScreenEdge
    var savedAt: Date
}

/// Shell-owned layout state the pill host view reads (which corner the content is pinned to).
@MainActor @Observable
final class PillChrome {
    var alignment: Alignment = .topTrailing
}

/// The floating pill: a non-activating panel that hovers open, snaps to edges, and remembers a spot per display.
@MainActor
final class PillController: NSObject, NSWindowDelegate {
    static let margin: CGFloat = 14          // transparent room around the content for the glass shadow
    private static let inset: CGFloat = 12   // visible gap between the pill and the screen edge
    private static let positionsKey = "pillPositions"
    private static let settleDelay = 0.45    // after the morph animation, shrink the window to the content

    private let state: NudgeState
    private let statusItemScreen: @MainActor () -> NSScreen?
    private let panel: PillPanelWindow
    private let chrome = PillChrome()

    /// The content corner the pill grows away from, in screen coordinates.
    private var corner = NSPoint.zero
    private var trailing = true
    private var top = true
    private var screenUUID: String?
    private var contentSize = CGSize(width: 150, height: 40)
    private var placed = false

    private var menuOpen = false
    private var hoverSuppressed = false
    private var popoversOpen = 0
    /// A child menu or popover (row hover card) is showing: stay expanded, ignore hover exits.
    private var holdOpen: Bool { menuOpen || popoversOpen > 0 }
    private struct Drag {
        var start: NSPoint
        var origin: NSPoint
        var moving = false
    }
    private var drag: Drag?
    private var exitTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var dimTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    init(state: NudgeState, intents: NudgeIntents, statusItemScreen: @escaping @MainActor () -> NSScreen?) {
        self.state = state
        self.statusItemScreen = statusItemScreen
        panel = PillPanelWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 70),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        super.init()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false   // dragging is handled by the event monitor in start()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.escape() }
        panel.setAccessibilityLabel("Nudge pill")

        let host = TrackingView()
        host.onEnter = { [weak self] in self?.mouseEntered() }
        host.onExit = { [weak self] in self?.mouseExited() }
        let hosting = makeHostingView(PillHost(state: state, intents: intents, chrome: chrome) { [weak self] in
            self?.contentSizeChanged($0)
        })
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)
        panel.contentView = host
    }

    func start() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuOpen = true }
        }
        nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuOpen = false
                self.collapseIfOutside()
            }
        }
        nc.addObserver(forName: NSPopover.willShowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.popoversOpen += 1 }
        }
        nc.addObserver(forName: NSPopover.didCloseNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.popoversOpen = max(0, self.popoversOpen - 1)
                self.collapseIfOutside()
            }
        }
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.place() }
        }
        // Click → key (so Esc works). A left drag past a few points moves the window by hand (SwiftUI content
        // defeats `isMovableByWindowBackground`, and `performDrag` doesn't track here), then snaps on mouse-up.
        // Right-clicks and control-clicks pass straight to SwiftUI's context menu: no key, no drag, no snap.
        // Local monitors only see Nudge's own events.
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                let mouse = NSEvent.mouseLocation
                switch event.type {
                case .leftMouseDown:
                    guard event.window === self.panel, !event.modifierFlags.contains(.control) else { return false }
                    self.drag = Drag(start: mouse, origin: self.panel.frame.origin)
                    self.panel.allowKey = true
                    self.panel.makeKey()
                    return false
                case .leftMouseDragged:
                    guard var drag = self.drag else { return false }
                    if !drag.moving, hypot(mouse.x - drag.start.x, mouse.y - drag.start.y) <= 4 { return false }
                    drag.moving = true
                    self.drag = drag
                    self.settleTask?.cancel()
                    self.panel.setFrameOrigin(NSPoint(x: drag.origin.x + mouse.x - drag.start.x,
                                                      y: drag.origin.y + mouse.y - drag.start.y))
                    return true
                default:
                    let moved = self.drag?.moving == true
                    self.drag = nil
                    if moved { self.snap() }
                    return moved
                }
            }
            return consumed ? nil : event
        }

        observeChanges({ [state] in Visibility(mode: state.settings.displayMode, hasRows: !state.rows.isEmpty) }) {
            [weak self] v in
            guard let self else { return }
            if v.mode != self.visibility?.mode { self.dismissed = false }   // a mode change ends a dismissal
            self.visibility = v
            self.updateVisibility()
        }
        observeChanges({ [state] in state.newRequestPulse }) { [weak self] _ in
            guard let self, self.dismissed else { return }
            self.dismissed = false                                         // so does a new request
            self.updateVisibility()
        }
        observeChanges({ [state] in Attention(tiers: state.rows.map(\.tier), pulse: state.newRequestPulse) }) {
            [weak self] _ in self?.wake()
        }
    }

    // MARK: Visibility

    private struct Visibility: Equatable, Sendable {
        var mode: DisplayMode
        var hasRows: Bool
    }

    private struct Attention: Equatable, Sendable {
        var tiers: [Tier]
        var pulse: Int
    }

    /// Hides the pill until the next new request or display-mode change. Not persisted across launches.
    func dismiss() {
        dismissed = true
        updateVisibility()
    }

    /// Undoes `dismiss()` (status item menu "Show Pill").
    func undismiss() {
        dismissed = false
        updateVisibility()
    }

    private(set) var dismissed = false
    private var visibility: Visibility?

    /// Shown now, or would be shown if it weren't dismissed.
    var isShown: Bool { panel.isVisible }
    var wouldShow: Bool {
        switch visibility?.mode {
        case .widgetAlways: true
        case .auto: visibility?.hasRows == true
        case .menuBarOnly, nil: false
        }
    }

    private func updateVisibility() {
        hideTask?.cancel()
        guard let v = visibility else { return }
        if dismissed { return hide() }
        switch v.mode {
        case .menuBarOnly: hide()
        case .widgetAlways: show()
        case .auto:
            if v.hasRows { show() }
            // Let the all-clear animation play before leaving.
            else if panel.isVisible { hideTask = after(1.2) { [weak self] in self?.hide() } }
        }
    }

    private func show() {
        guard !panel.isVisible else { return }
        if !placed { place() }
        panel.orderFrontRegardless()     // never makeKey: showing must not take focus
        scheduleDim()
    }

    private func hide() {
        guard panel.isVisible else { return }
        setExpanded(false)
        dimTask?.cancel()
        panel.orderOut(nil)
    }

    // MARK: Hover, expand, key

    /// Over the pill or one of its child windows (a row's hover card).
    private var mouseInside: Bool {
        let p = NSEvent.mouseLocation
        return panel.frame.contains(p) || (panel.childWindows ?? []).contains { $0.isVisible && $0.frame.contains(p) }
    }

    private func mouseEntered() {
        exitTask?.cancel()
        guard panel.isVisible, !hoverSuppressed else { return }
        setExpanded(true)
    }

    /// Resizing rebuilds the tracking area and can emit a spurious exit; debounce and confirm with the cursor.
    private func mouseExited() {
        exitTask?.cancel()
        exitTask = after(0.15) { [weak self] in
            guard let self, !self.mouseInside else { return }
            self.hoverSuppressed = false
            self.collapseIfOutside()
        }
    }

    /// Esc collapses while the pointer is still over the pill; don't re-expand until it really leaves.
    private func escape() {
        hoverSuppressed = true
        setExpanded(false)
    }

    private func collapseIfOutside() {
        if state.pillExpanded, !holdOpen, !mouseInside { setExpanded(false) }
    }

    private func setExpanded(_ expanded: Bool) {
        if expanded {
            dimTask?.cancel()
            state.pillDimmed = false
        } else {
            resignKey()
            scheduleDim()
        }
        guard state.pillExpanded != expanded else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { state.pillExpanded = expanded }
    }

    /// Gives keyboard focus back to the frontmost app: a key window that can no longer be key drops it on reorder.
    private func resignKey() {
        panel.allowKey = false
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    func windowDidResignKey(_ notification: Notification) { panel.allowKey = false }

    // MARK: Idle dim

    private func scheduleDim() {
        dimTask?.cancel()
        dimTask = after(3) { [weak self] in
            guard let self, !self.state.pillExpanded else { return }
            self.state.pillDimmed = true
        }
    }

    /// Full opacity for 3 s on a tier change or new request.
    private func wake() {
        state.pillDimmed = false
        scheduleDim()
    }

    // MARK: Size and placement

    /// Grow at once so a morph never clips; shrink only after the animation settles, so the frame never changes
    /// under the cursor mid-morph. The content stays pinned to `corner` throughout.
    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        let target = windowFrame(for: size)
        let current = panel.frame
        if target.width > current.width || target.height > current.height {
            panel.setFrame(current.union(target), display: true)
        }
        settleTask?.cancel()
        settleTask = after(Self.settleDelay) { [weak self] in self?.settle() }
    }

    private func settle() {
        panel.setFrame(windowFrame(for: contentSize), display: true)
        collapseIfOutside()
    }

    private func windowFrame(for size: CGSize) -> NSRect {
        contentFrame(for: size).insetBy(dx: -Self.margin, dy: -Self.margin)
    }

    private func contentFrame(for size: CGSize) -> NSRect {
        NSRect(x: trailing ? corner.x - size.width : corner.x, y: top ? corner.y - size.height : corner.y,
               width: size.width, height: size.height)
    }

    /// Puts the pill on the display it was last placed on (if connected), else the status item's display.
    private func place() {
        let saved = loadAnchors()
        let screens = NSScreen.screens
        let screen = screens.first { $0.displayUUID == screenUUID && screenUUID != nil }
            ?? screens.filter { saved[$0.displayUUID ?? ""] != nil }
                .max { saved[$0.displayUUID!]!.savedAt < saved[$1.displayUUID!]!.savedAt }
            ?? statusItemScreen() ?? NSScreen.main ?? screens.first
        guard let screen else { return }
        let vf = screen.visibleFrame
        screenUUID = screen.displayUUID
        if let a = saved[screenUUID ?? ""] {
            trailing = a.trailing
            top = a.top
            corner = NSPoint(x: vf.minX + a.fx * vf.width, y: vf.minY + a.fy * vf.height)
            state.pillEdge = a.edge
        } else {
            trailing = true
            top = true
            corner = NSPoint(x: vf.maxX - Self.inset, y: vf.maxY - Self.inset)
            state.pillEdge = .top
        }
        corner = clampedCorner(in: vf)
        chrome.alignment = alignment
        settleTask?.cancel()
        panel.setFrame(windowFrame(for: contentSize), display: true)
        placed = true
    }

    private var alignment: Alignment {
        switch (top, trailing) {
        case (true, true): .topTrailing
        case (true, false): .topLeading
        case (false, true): .bottomTrailing
        case (false, false): .bottomLeading
        }
    }

    /// Keeps the content rect inside the visible frame with the edge inset.
    private func clampedCorner(in vf: NSRect) -> NSPoint {
        let f = contentFrame(for: contentSize)
        let i = Self.inset
        let dx = max(vf.minX + i - f.minX, 0) + min(vf.maxX - i - f.maxX, 0)
        let dy = max(vf.minY + i - f.minY, 0) + min(vf.maxY - i - f.maxY, 0)
        return NSPoint(x: corner.x + dx, y: corner.y + dy)
    }

    /// On drag end: spring to the nearest edge of the current display (12 pt inset) and remember the spot.
    private func snap() {
        // Re-derive the corner from where the window was dropped, then fit the window to the content.
        let m = Self.margin, f = panel.frame
        corner = NSPoint(x: trailing ? f.maxX - m : f.minX + m, y: top ? f.maxY - m : f.minY + m)
        settleTask?.cancel()
        panel.setFrame(windowFrame(for: contentSize), display: false)

        let content = contentFrame(for: contentSize)
        let center = NSPoint(x: content.midX, y: content.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? panel.screen else { return }
        let vf = screen.visibleFrame, i = Self.inset
        let distances: [(ScreenEdge, CGFloat)] = [
            (.top, vf.maxY - content.maxY), (.bottom, content.minY - vf.minY),
            (.left, content.minX - vf.minX), (.right, vf.maxX - content.maxX),
        ]
        let edge = distances.min { $0.1 < $1.1 }!.0
        var target = content
        switch edge {
        case .top: target.origin.y = vf.maxY - i - target.height
        case .bottom: target.origin.y = vf.minY + i
        case .left: target.origin.x = vf.minX + i
        case .right: target.origin.x = vf.maxX - i - target.width
        }
        target.origin.x = min(max(target.origin.x, vf.minX + i), vf.maxX - i - target.width)
        target.origin.y = min(max(target.origin.y, vf.minY + i), vf.maxY - i - target.height)

        trailing = target.midX > vf.midX
        top = target.midY > vf.midY
        corner = NSPoint(x: trailing ? target.maxX : target.minX, y: top ? target.maxY : target.minY)
        chrome.alignment = alignment
        state.pillEdge = edge
        screenUUID = screen.displayUUID

        let frame = target.insetBy(dx: -m, dy: -m)
        if reduceMotion {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.2, 0.4, 1)   // slight spring overshoot
                panel.animator().setFrame(frame, display: true)
            }
        }
        saveAnchor(PillAnchor(trailing: trailing, top: top, fx: (corner.x - vf.minX) / vf.width,
                              fy: (corner.y - vf.minY) / vf.height, edge: edge, savedAt: Date()))
    }

    // MARK: Persistence (UserDefaults `pillPositions`, keyed by display UUID)

    private func loadAnchors() -> [String: PillAnchor] {
        guard let data = UserDefaults.standard.data(forKey: Self.positionsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PillAnchor].self, from: data)) ?? [:]
    }

    private func saveAnchor(_ anchor: PillAnchor) {
        guard let uuid = screenUUID else { return }
        var all = loadAnchors()
        all[uuid] = anchor
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: Self.positionsKey) }
    }
}

/// Pins `PillView` to the anchored corner so the window can grow and shrink around it without the content moving.
private struct PillHost: View {
    let state: NudgeState
    let intents: NudgeIntents
    let chrome: PillChrome
    let onSize: @MainActor (CGSize) -> Void

    var body: some View {
        MeasuredContent(alignment: chrome.alignment, margin: PillController.margin, onSize: onSize) {
            PillView(state: state, intents: intents)
        }
    }
}

/// Never key on hover or when shown; key only after a click inside (so Esc can collapse it).
final class PillPanelWindow: NSPanel {
    var allowKey = false
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Hover tracking that works while Nudge is inactive.
final class TrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
