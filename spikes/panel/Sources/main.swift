// Spike 4: status item + non-activating floating NSPanel hosting a SwiftUI glass capsule.
// Hover (NSTrackingArea .activeAlways) expands/collapses; Menu inside; Esc collapses; drag end snaps to edge.
// `--demo` expands at +2s and collapses at +6s without any input, for automated screenshots.
import AppKit
import SwiftUI
import os

let logger = Logger(subsystem: "io.github.foobarnes.nudge.spike-panel", category: "spike")
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/NudgeSpike/panel.log")

@MainActor func log(_ msg: String) {
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg) [frontmost=\(front)]"
    logger.notice("\(line, privacy: .public)")
    try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
    } else {
        try? (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }
}

let collapsedSize = NSSize(width: 150, height: 40)
let expandedSize = NSSize(width: 340, height: 170)
let inset: CGFloat = 12

@MainActor @Observable final class PillModel {
    var expanded = false
    var lastAction = "—"
}

struct PillView: View {
    @Bindable var model: PillModel

    var body: some View {
        // Container fills the panel; content pinned to the top-trailing corner (right edge default).
        VStack(alignment: .trailing) {
            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(.orange).frame(width: 8, height: 8)
                        Text("3").contentTransition(.numericText())
                        Text("·").foregroundStyle(.secondary)
                        Text("4h 12m").monospacedDigit()
                    }
                    .font(.system(.body, design: .rounded))
                    if model.expanded {
                        Divider()
                        row("api#4211", "Fix token refresh", "4:12:07")
                        row("web#930", "Export to CSV", "1:03:44")
                        HStack {
                            Menu("Start") {
                                Button("Check out locally") { model.lastAction = "checkout" }
                                Button("View diff") { model.lastAction = "diff" }
                            }
                            .fixedSize()
                            Menu("Snooze") {
                                Button("1 hour") { model.lastAction = "snooze 1h" }
                                Button("Until tomorrow") { model.lastAction = "snooze tomorrow" }
                            }
                            .fixedSize()
                            Spacer()
                            Text(model.lastAction).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: model.expanded ? 18 : 20))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.spring(duration: 0.35), value: model.expanded)
    }

    func row(_ ref: String, _ title: String, _ time: String) -> some View {
        HStack {
            Circle().fill(.red).frame(width: 7, height: 7)
            Text(ref).font(.callout.weight(.medium))
            Text(title).lineLimit(1).truncationMode(.tail)
            Spacer()
            Text(time).monospacedDigit().foregroundStyle(.red)
        }
        .font(.system(.callout, design: .rounded))
    }
}

final class PillPanel: NSPanel {
    var allowKey = false
    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }   // Esc while key
    var onEscape: (() -> Void)?
}

final class TrackingHostView: NSView {
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
    override func mouseDown(with event: NSEvent) {
        // Click on the pill background: allow key so Esc works, without activating the app.
        (window as? PillPanel)?.allowKey = true
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = PillModel()
    var panel: PillPanel!
    var statusItem: NSStatusItem!
    var menuOpen = false
    var dragStartOrigin: NSPoint?
    var collapseWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        log("launched")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clock.badge", accessibilityDescription: "Nudge spike")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = "3"
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle expand", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu

        panel = PillPanel(contentRect: NSRect(origin: .zero, size: collapsedSize),
                          styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.delegate = self
        panel.onEscape = { [weak self] in log("esc"); self?.setExpanded(false); self?.resignKey() }

        let host = TrackingHostView()
        let hosting = NSHostingView(rootView: PillView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: host.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        host.onEnter = { [weak self] in
            guard let self else { return }
            log("mouseEntered mouse=\(NSEvent.mouseLocation) inside=\(mouseInside)")
            setExpanded(true)
        }
        // Resizing the panel rebuilds the tracking area, which can emit an enter/exit pair while the
        // cursor never moved. Confirm against the real cursor position after a short debounce.
        host.onExit = { [weak self] in
            guard let self else { return }
            log("mouseExited mouse=\(NSEvent.mouseLocation) inside=\(mouseInside) menuOpen=\(menuOpen)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !self.menuOpen && !self.mouseInside { self.setExpanded(false) }
            }
        }
        panel.contentView = host

        let vf = NSScreen.main!.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: vf.maxX - collapsedSize.width - inset, y: vf.maxY - inset))
        panel.orderFrontRegardless()
        log("panel shown frame=\(panel.frame) isKey=\(panel.isKeyWindow) active=\(NSApp.isActive)")

        // Child menu tracking: keep expanded while a SwiftUI Menu (NSMenu) is open.
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuOpen = true; log("menu begin isKey=\(self?.panel.isKeyWindow ?? false)") }
        }
        nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuOpen = false
                log("menu end lastAction=\(self.model.lastAction)")
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.setExpanded(false) }
            }
        }
        // Drag end → snap. Local monitors only see events delivered to this app (i.e. on the panel).
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, e.window === self.panel else { return }
                if e.type == .leftMouseDown { self.dragStartOrigin = self.panel.frame.origin }
                else if let start = self.dragStartOrigin, start != self.panel.frame.origin { self.snap() }
            }
            return e
        }

        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.setExpanded(true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.setExpanded(false) }
        }
    }

    var mouseInside: Bool { panel.frame.contains(NSEvent.mouseLocation) }

    @objc func toggle() { setExpanded(!model.expanded) }

    func resignKey() {
        panel.allowKey = false
        panel.resignKey()
    }

    /// Grow the window before the morph; shrink only after the collapse animation finishes,
    /// so the frame never changes under the cursor mid-hover. Top-right corner stays fixed.
    func setExpanded(_ on: Bool) {
        guard on != model.expanded else { return }
        collapseWork?.cancel()
        let f = panel.frame
        if on {
            panel.setFrame(NSRect(x: f.maxX - expandedSize.width, y: f.maxY - expandedSize.height,
                                  width: expandedSize.width, height: expandedSize.height), display: true)
            model.expanded = true
        } else {
            model.expanded = false
            let work = DispatchWorkItem { [weak self] in
                guard let self, !model.expanded else { return }
                let f = panel.frame
                panel.setFrame(NSRect(x: f.maxX - collapsedSize.width, y: f.maxY - collapsedSize.height,
                                      width: collapsedSize.width, height: collapsedSize.height), display: true)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
        log("expanded=\(on) frame=\(panel.frame) isKey=\(panel.isKeyWindow)")
    }

    func snap() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame, f = panel.frame
        var o = f.origin
        let d = [("left", f.minX - vf.minX), ("right", vf.maxX - f.maxX),
                 ("bottom", f.minY - vf.minY), ("top", vf.maxY - f.maxY)].min { $0.1 < $1.1 }!
        switch d.0 {
        case "left": o.x = vf.minX + inset
        case "right": o.x = vf.maxX - f.width - inset
        case "bottom": o.y = vf.minY + inset
        default: o.y = vf.maxY - f.height - inset
        }
        o.x = min(max(o.x, vf.minX + inset), vf.maxX - f.width - inset)
        o.y = min(max(o.y, vf.minY + inset), vf.maxY - f.height - inset)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.2, 0.4, 1) // spring-ish overshoot
            panel.animator().setFrameOrigin(o)
        }
        log("snap edge=\(d.0) to=\(o)")
    }

    func windowDidBecomeKey(_ n: Notification) { log("panel didBecomeKey active=\(NSApp.isActive)") }
    func windowDidResignKey(_ n: Notification) { log("panel didResignKey"); panel.allowKey = false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
