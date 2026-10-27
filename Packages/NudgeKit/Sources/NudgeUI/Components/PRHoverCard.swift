import AppKit
import NudgeCore
import SwiftUI

/// Details card for a PR row. Independent of how it is presented (popover today, in-panel overlay if the shell needs it).
struct PRHoverCard: View {
    let row: PRRow
    let intents: NudgeIntents
    var now: Date = .now
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.pr.title)
                .font(Tokens.Typo.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { repoLine; dotSeparator; branchChip }
                VStack(alignment: .leading, spacing: 4) { repoLine; branchChip }
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
                Button(action: copyLink) {
                    Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
                        .contentTransition(.opacity)
                }
                .buttonStyle(MiniButtonStyle())
                .animation(Motion.crossfade, value: copied)
            }
            .labelStyle(MiniLabelStyle())
            .padding(.top, 2)
        }
        .padding(14)
        .frame(minWidth: 280, maxWidth: 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Tokens.Palette.text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Details for \(row.pr.title)")
    }

    private var dotSeparator: some View { Text("·") }

    private var repoLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(row.pr.repo) #\(row.pr.number)").fontWeight(.semibold)
            dotSeparator
            Text("by \(row.pr.author)")
        }
        .fixedSize()
    }

    private var branchChip: some View {
        Text(row.pr.headRef)
            .font(Tokens.Typo.codeSmall)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Tokens.Palette.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
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

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.pr.url.absoluteString, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            copied = false
        }
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
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    nonisolated init() {}

    var suppressed: Bool { scrolling || menuOpen || popoverOpen }

    func toggle(_ id: String) {
        openID = openID == id ? nil : id
    }

    func close(_ id: String) {
        if openID == id { openID = nil }
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

/// Hover intent: ~450ms over the trigger opens, instant when another card is already open,
/// ~200ms after leaving both row and card closes.
struct HoverCardPresenter: ViewModifier {
    let row: PRRow
    let intents: NudgeIntents
    let arrowEdge: Edge
    let triggerHovered: Bool
    let rowHovered: Bool
    @Environment(\.hoverCards) private var cards
    @State private var cardHovered = false
    @State private var openTask: Task<Void, Never>?
    @State private var closeTask: Task<Void, Never>?

    private var isPresented: Binding<Bool> {
        Binding(get: { cards.openID == row.id }, set: { if !$0 { cards.close(row.id) } })
    }

    func body(content: Content) -> some View {
        content
            .popover(isPresented: isPresented, arrowEdge: arrowEdge) {
                PRHoverCard(row: row, intents: intents)
                    .onHover { inside in
                        cardHovered = inside
                        inside ? cancelClose() : scheduleClose()
                    }
            }
            .onChange(of: triggerHovered) { _, inside in
                if inside { scheduleOpen() } else { openTask?.cancel() }
            }
            .onChange(of: rowHovered) { _, inside in
                if inside { cancelClose() } else if !cardHovered { scheduleClose() }
            }
            .onChange(of: cards.suppressed) { _, suppressed in
                if suppressed { openTask?.cancel(); cards.close(row.id) }
            }
            .onDisappear { openTask?.cancel(); closeTask?.cancel(); cards.close(row.id) }
            .accessibilityCustomContent(Text("Details"), Text(verbatim: PRHoverCard(row: row, intents: intents).summary))
            .accessibilityAction(named: "Show details") { cards.toggle(row.id) }
    }

    private func scheduleOpen() {
        guard !cards.suppressed else { return }
        openTask?.cancel()
        closeTask?.cancel()
        if let open = cards.openID, open != row.id {
            cards.openID = row.id
            return
        }
        openTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, !cards.suppressed else { return }
            cards.openID = row.id
        }
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
    func hoverCard(row: PRRow, intents: NudgeIntents, arrowEdge: Edge, triggerHovered: Bool, rowHovered: Bool) -> some View {
        modifier(HoverCardPresenter(row: row, intents: intents, arrowEdge: arrowEdge,
                                    triggerHovered: triggerHovered, rowHovered: rowHovered))
    }
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
