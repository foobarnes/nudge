import AppKit
import NudgeCore
import SwiftUI

/// Details card for a PR row. Independent of how it is presented (popover today, in-panel overlay if the shell needs it).
struct PRHoverCard: View {
    let row: PRRow
    let intents: NudgeIntents
    var now: Date = .now
    @State private var copiedLink = false
    @State private var copiedBranch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.pr.title)
                .font(Tokens.Typo.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 6) {
                repoLine
                branchLine
            }
            .font(Tokens.Typo.rowSubtitle)
            .foregroundStyle(Tokens.Palette.secondary)

            Text(requestLine).font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.secondary)

            timeLine

            if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.text) { chip in
                        Chip(symbol: chip.symbol, text: chip.text, fill: chip.fill, color: chip.color)
                    }
                }
            }

            HStack(spacing: Tokens.Space.actionsGap) {
                Button { intents.open(row) } label: { Label("Open on GitHub", systemImage: "arrow.up.right") }
                    .buttonStyle(MiniButtonStyle(role: .primary))
                Button { copy(row.pr.url.absoluteString, flag: $copiedLink) } label: {
                    Label(copiedLink ? "Copied" : "Copy link", systemImage: copiedLink ? "checkmark" : "link")
                        .contentTransition(.opacity)
                }
                .buttonStyle(MiniButtonStyle())
                .animation(Motion.crossfade, value: copiedLink)
            }
            .labelStyle(MiniLabelStyle())
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)   // fixed: a width range measures the branch unwrapped and clips its height
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Tokens.Palette.text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Details for \(row.pr.title)")
    }

    private var repoLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(row.pr.repo) #\(row.pr.number)").fontWeight(.semibold)
            Text("·")
            Text("by \(row.pr.author)")
        }
        .fixedSize()
    }

    /// The branch wraps (up to three lines; the card never clips it) with a copy button beside it.
    private var branchLine: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(row.pr.headRef)
                .font(Tokens.Typo.codeSmall)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Tokens.Palette.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            CopyIconButton(copied: copiedBranch, label: "Copy branch name") { copy(row.pr.headRef, flag: $copiedBranch) }
        }
    }

    private var requestLine: String {
        switch row.pr.via {
        case .direct:
            var line = row.pr.requestedBy.map { "\($0) requested your review" } ?? "Review requested"
            if let at = row.pr.requestedAt { line += " · \(Format.weekdayTimeIfNotToday(at, now: now))" }
            return line
        case let .team(org, slug):
            var line = "Requested from \(org)/\(slug)"
            let others = row.pr.otherTeams.map(\.label)
            if !others.isEmpty { line += " · also \(others.joined(separator: ", "))" }
            if let at = row.pr.requestedAt { line += " · \(Format.weekdayTimeIfNotToday(at, now: now))" }
            return line
        }
    }

    @ViewBuilder private var timeLine: some View {
        if let since = row.pr.waitingSince {
            let waiting = Text(verbatim: "Waiting \(DurationFormat.compact(now.timeIntervalSince(since)))").bold()
            let work = Text(verbatim: " · \(DurationFormat.compact(row.workSeconds ?? 0)) of work time")
                .foregroundStyle(Tokens.Palette.secondary)
            Text("\(waiting)\(work)")
                .font(Tokens.Typo.settingsBody)
                .monospacedDigit()
        } else {
            Text("Request time unknown").font(Tokens.Typo.settingsBody).foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private struct ChipSpec { let symbol: String; let text: String; let fill: Color; let color: Color }

    private var chips: [ChipSpec] {
        var chips: [ChipSpec] = []
        if let until = row.snoozedUntil {
            chips.append(ChipSpec(symbol: "moon.fill", text: "Snoozed until \(Format.weekdayTimeIfNotToday(until, now: now))",
                                  fill: Tokens.Palette.fill, color: Tokens.Palette.secondary))
        }
        if row.level == .silent {
            chips.append(ChipSpec(symbol: "bell.slash.fill", text: "Silent", fill: Tokens.Palette.fill, color: Tokens.Palette.secondary))
        }
        if row.tier != .fresh {
            chips.append(ChipSpec(symbol: "circle.fill", text: row.tier == .amber ? "Amber" : "Red",
                                  fill: Tokens.Tier.chipFill(row.tier), color: Tokens.Tier.text(row.tier)))
        }
        return chips
    }

    /// Spoken summary for VoiceOver custom content.
    var summary: String {
        var parts = [requestLine]
        if let since = row.pr.waitingSince {
            parts.append("waiting \(Format.spoken(now.timeIntervalSince(since))), \(Format.spoken(row.workSeconds ?? 0)) of work time")
        } else {
            parts.append("request time unknown")
        }
        parts.append(contentsOf: chips.map(\.text))
        return parts.joined(separator: ". ")
    }

    /// Copies `text` and raises `flag` for 1.5s so the button can show a check.
    private func copy(_ text: String, flag: Binding<Bool>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flag.wrappedValue = true
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            flag.wrappedValue = false
        }
    }
}

/// 20pt copy glyph that turns into a green check while `copied` is set. Arrow cursor, like every button.
struct CopyIconButton: View {
    let copied: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? Tokens.Palette.check : Tokens.Palette.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(CopyIconButtonStyle())
        .focusable(false)
        .animation(Motion.crossfade, value: copied)
        .accessibilityLabel(copied ? "Copied" : label)
    }
}

private struct CopyIconButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .frame(width: 20, height: 20)
            .background(Tokens.Palette.text.opacity(configuration.isPressed ? 0.18 : hovered ? 0.11 : 0), in: shape)
            .contentShape(shape)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Presentation

/// Which row's card is open, plus the conditions that keep cards closed (scrolling, an open menu or popover).
@MainActor @Observable
final class HoverCardCoordinator {
    var openID: String?
    var scrolling = false
    var menuOpen = false
    var popoverOpen = false
    /// Bumped by any row click. Presenters drop their pending open so a card never pops right after a click.
    private(set) var clicks = 0
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    nonisolated init() {}

    var suppressed: Bool { scrolling || menuOpen || popoverOpen }

    func toggle(_ id: String) {
        openID = openID == id ? nil : id
    }

    func close(_ id: String) {
        if openID == id { openID = nil }
    }

    /// A row was clicked (open, start, snooze, hide): the card is done.
    func rowClicked() {
        openID = nil
        clicks += 1
    }

    /// Tracks NSMenu sessions (Start ⌄ and the system menus) so cards never open under a menu.
    func activate() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.menuOpen = true; self.openID = nil }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.menuOpen = false }
            },
        ]
    }
}

extension EnvironmentValues {
    @Entry var hoverCards = HoverCardCoordinator()
}

/// Hover intent: ~450ms over the title or subtitle opens, ~900ms anywhere else on the row (never over the action
/// buttons), instant when another card is already open, ~200ms after leaving both row and card closes.
struct HoverCardPresenter: ViewModifier {
    static let textDelay: Duration = .milliseconds(450)
    static let rowDelay: Duration = .milliseconds(900)

    let row: PRRow
    let intents: NudgeIntents
    let arrowEdge: Edge
    let textHovered: Bool
    let rowHovered: Bool
    let actionsHovered: Bool
    @Environment(\.hoverCards) private var cards
    @State private var cardHovered = false
    @State private var openTask: Task<Void, Never>?
    @State private var deadline: ContinuousClock.Instant?
    @State private var closeTask: Task<Void, Never>?

    private var isPresented: Binding<Bool> {
        Binding(get: { cards.openID == row.id }, set: { if !$0 { cards.close(row.id) } })
    }

    func body(content: Content) -> some View {
        content
            .anchoredPopover(isPresented: isPresented, arrowEdge: arrowEdge) {
                PRHoverCard(row: row, intents: intents)
                    .onHover { inside in
                        cardHovered = inside
                        inside ? cancelClose() : scheduleClose()
                    }
            }
            .onChange(of: rowHovered) { _, inside in
                if inside { arm(after: Self.rowDelay) } else { disarm(); if !cardHovered { scheduleClose() } }
            }
            .onChange(of: textHovered) { _, inside in
                if inside { arm(after: Self.textDelay) }
            }
            .onChange(of: actionsHovered) { _, inside in
                if inside { disarm() } else if rowHovered { arm(after: Self.rowDelay) }
            }
            .onChange(of: cards.clicks) { _, _ in disarm() }
            .onChange(of: cards.suppressed) { _, suppressed in
                if suppressed { disarm(); cards.close(row.id) }
            }
            .onDisappear { disarm(); closeTask?.cancel(); cards.close(row.id) }
            .accessibilityCustomContent(Text("Details"), Text(verbatim: PRHoverCard(row: row, intents: intents).summary))
            .accessibilityAction(named: "Show details") { cards.toggle(row.id) }
    }

    /// Opens after `delay`, unless an earlier deadline is already pending. Switches instantly between open cards.
    private func arm(after delay: Duration) {
        guard !cards.suppressed, !actionsHovered else { return }
        closeTask?.cancel()
        if let open = cards.openID, open != row.id {
            cards.openID = row.id
            return
        }
        let target = ContinuousClock.now + delay
        if let deadline, deadline <= target { return }
        openTask?.cancel()
        deadline = target
        openTask = Task {
            try? await Task.sleep(until: target, clock: .continuous)
            guard !Task.isCancelled else { return }
            deadline = nil
            if !cards.suppressed { cards.openID = row.id }
        }
    }

    private func disarm() {
        openTask?.cancel()
        openTask = nil
        deadline = nil
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, !cardHovered, !rowHovered else { return }
            cards.close(row.id)
        }
    }

    private func cancelClose() { closeTask?.cancel() }
}

extension View {
    func hoverCard(row: PRRow, intents: NudgeIntents, arrowEdge: Edge,
                   textHovered: Bool, rowHovered: Bool, actionsHovered: Bool = false) -> some View {
        modifier(HoverCardPresenter(row: row, intents: intents, arrowEdge: arrowEdge,
                                    textHovered: textHovered, rowHovered: rowHovered, actionsHovered: actionsHovered))
    }

    /// An `NSPopover` with `.applicationDefined` behavior anchored to this view: a click outside it is never swallowed
    /// (it reaches the row underneath), so the caller closes it by hover intent through `isPresented`.
    /// SwiftUI's `.popover` is transient and eats the dismissing click, which is why a row click under an open
    /// card used to do nothing.
    func anchoredPopover<Content: View>(isPresented: Binding<Bool>, arrowEdge: Edge,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        background { AnchoredPopover(isPresented: isPresented, arrowEdge: arrowEdge, content: content) }
    }
}

private struct AnchoredPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let arrowEdge: Edge
    let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onClose = { isPresented = false }
        coordinator.wantsShown = isPresented
        if isPresented {
            let popover = coordinator.popover(for: content())
            guard !popover.isShown else { return }
            DispatchQueue.main.async {
                guard coordinator.wantsShown, !popover.isShown, view.window != nil else { return }
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
            }
        } else if let popover = coordinator.popoverIfLoaded, popover.isShown {
            popover.close()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.wantsShown = false
        coordinator.popoverIfLoaded?.close()
    }

    /// SwiftUI's `arrowEdge` names the anchor edge the arrow touches; so does `preferredEdge` in an unflipped view.
    private var edge: NSRectEdge {
        switch arrowEdge {
        case .top: .maxY
        case .bottom: .minY
        case .leading: .minX
        case .trailing: .maxX
        }
    }

    @MainActor final class Coordinator: NSObject, NSPopoverDelegate {
        var wantsShown = false
        var onClose: () -> Void = {}
        private(set) var host: PopoverContentController<Content>?
        private(set) var popoverIfLoaded: NSPopover?

        func popover(for content: Content) -> NSPopover {
            if let popover = popoverIfLoaded, let host {
                host.rootView = content
                return popover
            }
            let host = PopoverContentController(rootView: content)
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = true
            popover.contentViewController = host
            popover.delegate = self
            self.host = host
            popoverIfLoaded = popover
            return popover
        }

        nonisolated func popoverDidClose(_ notification: Notification) {
            MainActor.assumeIsolated { if wantsShown { onClose() } }
        }
    }
}

/// Hosts the popover's SwiftUI content in a view that takes the first click. Nudge is never the active app, so
/// without this the first click on a card button only "activates" the popover window and is lost.
private final class PopoverContentController<Content: View>: NSViewController {
    private let hosting: FirstMouseHostingView<Content>

    init(rootView: Content) {
        hosting = FirstMouseHostingView(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = hosting
        fit()
    }

    var rootView: Content {
        get { hosting.rootView }
        set { hosting.rootView = newValue; fit() }
    }

    private func fit() { preferredContentSize = hosting.fittingSize }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// A click makes the popover window active, and an active popover draws its content with vibrant blending,
    /// which washes the secondary text out. The card's own colors are tuned for glass already.
    override var allowsVibrancy: Bool { false }
}

extension ScreenEdge {
    /// Popover arrow edge that opens the card away from the snapped screen edge.
    var cardArrowEdge: Edge {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .left: .trailing
        case .right: .leading
        }
    }
}
