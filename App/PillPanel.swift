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
    private static let settleDelay = 0.45    // after a content change animates, fit the window to the content

    private let state: NudgeState
    private let statusItemScreen: @MainActor () -> NSScreen?
    private let panel: PillPanelWindow
    private let chrome = PillChrome()

    /// The content corner the pill grows away from, in screen coordinates.
    private var corner = NSPoint.zero
    private var trailing = true
    private var top = true
    private var screenUUID: String?
    /// Natural sizes of the pill in both states, reported by `PillView`.
    private var sizes = PillSizes()
    private var placed = false
    /// What the window should fit right now (the pill's state, not the morph in flight).
    private var contentSize: CGSize {
        let size = state.pillExpanded ? sizes.expanded : sizes.collapsed
        return size.width > 0 && size.height > 0 ? size : CGSize(width: 150, height: 40)
    }

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
    private var testingHold = false
    private var exitTask: Task<Void, Never>?
    private var entryTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var dimTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var glideLink: CADisplayLink?
    private var glideFrom = NSPoint.zero
    private var glideTo = NSPoint.zero
    private var glideStart: CFTimeInterval = 0

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
        panel.animationBehavior = .none   // resignKey() reorders the panel; a fade there flashes the pill out
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.escape() }
        panel.setAccessibilityLabel("Nudge pill")

        let host = TrackingView()
        host.onEnter = { [weak self] in self?.mouseEntered() }
        host.onExit = { [weak self] in self?.mouseExited() }
        let hosting = makeHostingView(PillHost(state: state, intents: intents, chrome: chrome) { [weak self] in
            self?.sizesChanged($0)
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
                    self.stopGlide()
                    self.drag = Drag(start: mouse, origin: self.panel.frame.origin)
                    return false
                case .leftMouseDragged:
                    guard var drag = self.drag else { return false }
                    if !drag.moving, hypot(mouse.x - drag.start.x, mouse.y - drag.start.y) <= 4 { return false }
                    drag.moving = true
                    self.drag = drag
                    self.settleTask?.cancel()
                    self.entryTask?.cancel()
                    self.exitTask?.cancel()
                    self.panel.setFrameOrigin(NSPoint(x: drag.origin.x + mouse.x - drag.start.x,
                                                      y: drag.origin.y + mouse.y - drag.start.y))
                    return true
                default:
                    let moved = self.drag?.moving == true
                    self.drag = nil
                    if moved {
                        self.snap()
                    } else if !self.state.rows.isEmpty {
                        // A click on the card: key so Esc works. Key restyles the glass, so the bare
                        // capsule (nothing to collapse) never takes it, and neither does a drag.
                        self.panel.allowKey = true
                        self.panel.makeKey()
                    }
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
        guard drag?.moving != true, glideLink == nil else { return }
        guard panel.isVisible, !hoverSuppressed else { return }
        // While a collapse settles the window is still card-sized; only the capsule itself expands the pill.
        if !state.pillExpanded, !capsuleContains(NSEvent.mouseLocation) {
            entryTask?.cancel()
            entryTask = Task { [weak self] in
                while let self, !Task.isCancelled, self.panel.frame.contains(NSEvent.mouseLocation) {
                    if self.capsuleContains(NSEvent.mouseLocation) { self.setExpanded(true); return }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            return
        }
        setExpanded(true)
    }

    private func capsuleContains(_ point: NSPoint) -> Bool {
        contentFrame(for: sizes.collapsed).insetBy(dx: -4, dy: -4).contains(point)
    }

    /// Resizing rebuilds the tracking area and can emit a spurious exit; debounce and confirm with the cursor.
    private func mouseExited() {
        exitTask?.cancel()
        entryTask?.cancel()
        guard drag?.moving != true, glideLink == nil else { return }
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

    /// DEBUG launch args drive the morph without a pointer (hang and CPU checks).
    func setExpandedForTesting(_ expanded: Bool) {
        guard panel.isVisible else { return }
        testingHold = expanded          // the pointer isn't over the pill, so don't auto-collapse
        hoverSuppressed = !expanded
        setExpanded(expanded)
    }

    /// DEBUG: drop the pill at a point (as if dragged there) and let it snap, for checks without a pointer.
    var screenForTesting: NSScreen? { panel.screen }

    func dropForTesting(at point: NSPoint) {
        panel.setFrameOrigin(point)
        snap()
    }

    private func collapseIfOutside() {
        if state.pillExpanded, !holdOpen, !mouseInside, !testingHold { setExpanded(false) }
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
        settleTask?.cancel()
        resizeTask?.cancel()
        if expanded {
            // Size the (clear) window to the card first, anchored at `corner`, so the morph never touches the
            // window and the capsule's corner stays put. `PillView` animates the shape and content itself.
            panel.setFrame(windowFrame(for: sizes.expanded), display: false)
            state.pillExpanded = true
        } else {
            state.pillExpanded = false
            // Shrink only once the collapse morph has landed back on the capsule.
            settleTask = after(PillView.collapseDuration(reduceMotion: reduceMotion)) { [weak self] in self?.settle() }
        }
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

    /// Content changed size (a row came or went, the count grew): grow at once so nothing clips, shrink after the
    /// change has animated. Morphs never come through here; `setExpanded` sizes the window for them.
    ///
    /// Reported from inside SwiftUI's layout pass: resizing the window synchronously here re-enters
    /// `NSHostingView.layout()`, so the resize is deferred to the next run-loop turn.
    private func sizesChanged(_ new: PillSizes) {
        guard new != sizes else { return }
        sizes = new
        guard placed else { return }
        resizeTask?.cancel()
        resizeTask = after(0) { [weak self] in self?.grow() }
    }

    private func grow() {
        let target = windowFrame(for: contentSize)
        let current = panel.frame
        if target.width > current.width || target.height > current.height {
            panel.setFrame(current.union(target), display: false)
        }
        settleTask?.cancel()
        settleTask = after(Self.settleDelay) { [weak self] in self?.settle() }
    }

    private func settle() {
        panel.setFrame(windowFrame(for: contentSize), display: false)
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
        placed = true   // before the first setFrame: its layout reports the pill's sizes, which must then apply
        panel.setFrame(windowFrame(for: contentSize), display: true)
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

    /// Springs the window's origin to `target` one display frame at a time. `NSAnimationContext` frame animations
    /// only land a few frames on this panel (each step relays out and redraws the glass), so the snap jumped.
    private func glide(to target: NSPoint) {
        glideLink?.invalidate()
        glideFrom = panel.frame.origin
        glideTo = target
        glideStart = CACurrentMediaTime()
        let link = panel.displayLink(target: self, selector: #selector(glideStep(_:)))
        link.add(to: .main, forMode: .common)
        glideLink = link
    }

    @objc private func glideStep(_ link: CADisplayLink) {
        // Underdamped spring (response 0.4 s, damping 0.8): a slight overshoot, settled in about half a second.
        let t = CACurrentMediaTime() - glideStart
        let omega = 2 * Double.pi / 0.4, zeta = 0.8
        let wd = omega * (1 - zeta * zeta).squareRoot()
        let p = 1 - exp(-zeta * omega * t) * (cos(wd * t) + zeta * omega / wd * sin(wd * t))
        let done = t >= 0.7
        let k = done ? 1 : CGFloat(p)
        panel.setFrameOrigin(NSPoint(x: glideFrom.x + (glideTo.x - glideFrom.x) * k,
                                     y: glideFrom.y + (glideTo.y - glideFrom.y) * k))
        if done {
            stopGlide()
            collapseIfOutside()   // hover exits were held while the window moved
        }
    }

    private func stopGlide() {
        glideLink?.invalidate()
        glideLink = nil
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
            panel.setFrameOrigin(frame.origin)
        } else {
            glide(to: frame.origin)
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

/// Pins `PillView` to the anchored corner inside a root that fills the window, so the window can be sized around
/// it without the content moving; `PillView` reports its collapsed and expanded sizes for that.
private struct PillHost: View {
    let state: NudgeState
    let intents: NudgeIntents
    let chrome: PillChrome
    let onSize: @MainActor (PillSizes) -> Void

    var body: some View {
        // The pill's layout size is always its card size; as an overlay its anchor corner stays at the root's
        // corner even while the window is only capsule-sized (a frame would centre the overflow instead).
        Color.clear
            .overlay(alignment: chrome.alignment) {
                PillView(state: state, intents: intents, anchor: chrome.alignment)
                    .onPreferenceChange(PillSizesKey.self) { sizes in MainActor.assumeIsolated { onSize(sizes) } }
            }
            .padding(PillController.margin)
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
