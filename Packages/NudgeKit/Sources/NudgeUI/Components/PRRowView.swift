import AppKit
import NudgeCore
import SwiftUI

/// One request, shared by the expanded pill and the dropdown. The whole row is one button that opens the PR
/// (pointing-hand cursor, hover and pressed fills); only the action buttons on the second line are their own
/// targets. Hover (or keyboard focus) cross-fades the work chip into the icon actions, and while the pointer is
/// over one of them the subtitle becomes that button's name. The timer never moves.
struct PRRowView: View {
    let row: PRRow
    let state: NudgeState
    let intents: NudgeIntents
    var live = false
    var isActive = false
    var cardEdge: Edge = .bottom
    @Environment(\.hoverCards) private var cards
    @State private var hovered = false
    @State private var textHovered = false
    @State private var actionsHovered = false
    @State private var showSnooze = false
    @State private var showBreakdown = false
    @State private var breakdownTask: Task<Void, Never>?
    @State private var actionLabel = ActionLabel()

    private var isTeam: Bool { row.pr.via.isTeam }
    private var revealed: Bool { hovered || isActive || showSnooze }

    var body: some View {
        Button { act { intents.open(row) } } label: { content }
            .buttonStyle(RowButtonStyle(highlighted: revealed, tint: rowTint))
            .focusable(false)
            .onHover { hovered = $0 }
            .hoverCard(row: row, intents: intents, arrowEdge: cardEdge,
                       textHovered: textHovered, rowHovered: hovered, actionsHovered: actionsHovered)
            .contextMenu {
                RowContextMenu(row: row, state: state, intents: intents,
                               customSnooze: { showSnooze = true }, showDetails: { cards.toggle(row.id) })
            }
            .onChange(of: showSnooze || showBreakdown) { _, open in cards.popoverOpen = open }
            .motion(Motion.crossfade, value: revealed)
            .motion(Motion.tint, value: row.tier)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityHint("Opens the pull request")
            .accessibilityAction(named: "Start review") { intents.startReview(row, nil) }
            .accessibilityAction(named: "Snooze") { intents.snooze(row, state.settings.defaultSnooze) }
            .accessibilityAction(named: "Hide") { intents.hide(row) }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Tokens.Space.rowGap) {
            TierDot(tier: row.tier, isTeam: isTeam, dimmed: state.isOffHours)
                .transition(.symbolEffect(.drawOn))
                .padding(.top, 4)
            VStack(spacing: Tokens.Space.rowLines) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.pr.title)
                        .font(Tokens.Typo.rowTitle)
                        .foregroundStyle(isTeam ? Tokens.Palette.secondary : Tokens.Palette.text)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onHover { textHovered = $0 }
                    TimerText(since: row.pr.waitingSince, tier: row.tier, live: live)
                        .onHover(perform: hoverTimer)
                        .anchoredPopover(isPresented: $showBreakdown, arrowEdge: .bottom) {
                            WorkTimePopover(row: row, config: state.settings.workHours, thresholds: state.settings.thresholds)
                        }
                }
                HStack(alignment: .center, spacing: 12) {
                    subtitle
                    ZStack(alignment: .trailing) {
                        WorkChip(seconds: row.workSeconds, tier: row.tier).opacity(revealed ? 0 : 1)
                        actions.opacity(revealed ? 1 : 0)
                    }
                    .frame(height: IconButtonStyle.height)
                    .animation(.easeOut(duration: 0.15), value: revealed)
                }
            }
        }
        .padding(.horizontal, Tokens.Space.rowH)
        .padding(.vertical, Tokens.Space.rowV)
        .background { CursorArea(cursor: actionsHovered ? .arrow : .pointingHand) }
    }

    /// `owner/repo #n · author`, or the hovered action button's name in the same spot (0.12s cross-fade).
    private var subtitle: some View {
        let label = actionLabel.text
        return Text(label ?? row.subtitle)
            .font(label == nil ? Tokens.Typo.rowSubtitle : Tokens.Typo.rowSubtitle.weight(.semibold))
            .foregroundStyle(Tokens.Palette.secondary)
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.12), value: label)
            .onHover { textHovered = $0 }
            .accessibilityHidden(label != nil)
    }

    /// Their own click targets inside the row button: arrow cursor, and no hover card while the pointer is over them.
    private var actions: some View {
        HStack(spacing: 10) {
            SplitIconMenuButton(symbol: "play.fill", label: "Start review", menuLabel: "Run one action", role: .accent) {
                act { intents.startReview(row, nil) }
            } menu: {
                ForEach(state.settings.actions) { action in
                    Button { act { intents.startReview(row, action.id) } } label: { Label(action.name, systemImage: action.symbol) }
                }
                if state.settings.actions.isEmpty { Text("No actions yet") }
            }
            SplitIconPopoverButton(symbol: "moon.zzz", label: "Snooze \(state.settings.defaultSnooze.longLabel)",
                                   menuLabel: "More snooze options", isPresented: $showSnooze) {
                act { intents.snooze(row, state.settings.defaultSnooze) }
            } popover: {
                SnoozeMenu(row: row, state: state, intents: intents) { showSnooze = false }
            }
            IconButton(symbol: "eye.slash", label: "Hide until re-requested") { act { intents.hide(row) } }
            IconButton(symbol: "arrow.up.right", label: "Open on GitHub", role: .secondary) { act { intents.open(row) } }
        }
        .fixedSize()
        .onHover { actionsHovered = $0 }
        .environment(\.actionLabel, actionLabel)
        .onChange(of: revealed) { _, shown in if !shown { actionLabel.text = nil } }
        .accessibilityHidden(!revealed)
    }

    private var rowTint: Color {
        Tokens.Tier.rowTint(row.tier) ?? .clear
    }

    /// Any click on the row closes its card first, so the card never lingers over (or pops after) the action.
    private func act(_ action: () -> Void) {
        cards.rowClicked()
        action()
    }

    private func hoverTimer(_ inside: Bool) {
        breakdownTask?.cancel()
        if inside {
            breakdownTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { showBreakdown = true }
            }
        } else {
            showBreakdown = false
        }
    }
}

/// The row as a button: pointing hand, `fillHover` while hovered (or active, or with its snooze menu open),
/// `fillStrong` while pressed, over the faint tier tint.
struct RowButtonStyle: ButtonStyle {
    let highlighted: Bool
    var tint: Color = .clear

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
        configuration.label
            .background {
                shape.fill(fill(pressed: configuration.isPressed))
                    .background(tint, in: shape)
            }
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func fill(pressed: Bool) -> Color {
        if pressed { return Tokens.Palette.fillStrong }
        return highlighted ? Tokens.Palette.fillHover : .clear
    }
}

/// Sets the cursor while the pointer is over the view. SwiftUI's `.pointerStyle` relies on cursor-update events,
/// which the non-activating pill panel never receives, so the row sets `NSCursor` itself from an always-active
/// tracking area, and re-asserts it on every move because AppKit's idea of the current cursor can drift from what
/// the window server shows for an inactive app. Never hit-tested: clicks go to the SwiftUI content around it.
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorAreaView { BackgroundCursor.enable(); return CursorAreaView() }

    func updateNSView(_ view: CursorAreaView, context: Context) { view.cursor = cursor }

    final class CursorAreaView: NSView {
        var cursor: NSCursor = .arrow {
            didSet { if inside, cursor != oldValue { cursor.set() } }
        }
        private var inside = false
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) { inside = true; cursor.set() }
        override func mouseMoved(with event: NSEvent) { if inside { cursor.set() } }
        override func mouseExited(with event: NSEvent) { inside = false; NSCursor.arrow.set() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil, inside { inside = false; NSCursor.arrow.set() }
        }
    }
}

/// The window server ignores cursor changes from an inactive app unless its connection sets
/// `SetsCursorInBackground`. Private CoreGraphics API (as used by Hammerspoon, Rectangle, and others), looked up at
/// run time: if either symbol is missing the cursor simply stays an arrow.
@MainActor enum BackgroundCursor {
    private static var enabled = false

    static func enable() {
        guard !enabled else { return }
        enabled = true
        typealias MainConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let main = dlsym(handle, "CGSMainConnectionID"), let set = dlsym(handle, "CGSSetConnectionProperty")
        else { return }
        let cid = unsafeBitCast(main, to: MainConnection.self)()
        _ = unsafeBitCast(set, to: SetProperty.self)(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

/// Icon + title for the 26pt text buttons (hover card, dropdown header).
struct MiniLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}
