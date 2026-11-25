import AppKit
import SwiftUI

// A small glass label under an icon button, shown after the pointer rests on it. System tooltips (`.help`) never
// show while Nudge is inactive, which is always for the pill and dropdown, so this draws its own: a borderless child
// window that ignores the mouse, so it is never clipped by the panel or a scroll view and never takes a click.

extension View {
    /// Shows `text` (and a dimmer `shortcut`) under this view while the pointer rests on it. Hidden on any click.
    func tooltip(_ text: String, shortcut: String? = nil) -> some View {
        modifier(TooltipModifier(text: text, shortcut: shortcut))
    }
}

private struct TooltipModifier: ViewModifier {
    static let delay = Duration.milliseconds(500)

    let text: String
    let shortcut: String?
    @State private var hovering = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .task(id: hovering) {
                guard hovering else { shown = false; return }
                try? await Task.sleep(for: Self.delay)
                if !Task.isCancelled { shown = true }
            }
            .background(TooltipAnchor(shown: $shown, bubble: TooltipBubble(text: text, shortcut: shortcut)))
    }
}

struct TooltipBubble: View {
    let text: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(text).foregroundStyle(Tokens.Palette.text)
            if let shortcut { Text(shortcut).foregroundStyle(Tokens.Palette.secondary) }
        }
        .font(Tokens.Typo.caption)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9).padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .padding(2)   // room for the glass edge inside the window
    }
}

/// Places the bubble's window centred under the anchor view, or above it when there's no room below.
private struct TooltipAnchor: NSViewRepresentable {
    static let gap: CGFloat = 4

    @Binding var shown: Bool
    let bubble: TooltipBubble

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let c = context.coordinator
        c.onClick = { shown = false }
        if shown { c.show(bubble, below: view) } else { c.hide() }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.hide() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var onClick: () -> Void = {}
        private var window: NSPanel?
        private var clickMonitor: Any?

        func show(_ bubble: TooltipBubble, below anchor: NSView) {
            guard let parent = anchor.window, parent.isVisible, let screen = parent.screen else { return }
            let host = NSHostingView(rootView: bubble)
            let size = host.fittingSize
            let panel = window ?? Self.makePanel()
            panel.appearance = parent.effectiveAppearance
            panel.contentView = host

            let a = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let visible = screen.visibleFrame
            var origin = CGPoint(x: a.midX - size.width / 2, y: a.minY - TooltipAnchor.gap - size.height)
            if origin.y < visible.minY { origin.y = a.maxY + TooltipAnchor.gap }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - 4 - size.width)
            panel.setFrame(CGRect(origin: origin, size: size).integral, display: true)

            if window == nil {
                window = panel
                panel.alphaValue = 0
                parent.addChildWindow(panel, ordered: .above)
                NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
            }
            if clickMonitor == nil {
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    self?.onClick()
                    return event
                }
            }
        }

        func hide() {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            guard let window else { return }
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
            self.window = nil
        }

        private static func makePanel() -> NSPanel {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            return panel
        }
    }
}
