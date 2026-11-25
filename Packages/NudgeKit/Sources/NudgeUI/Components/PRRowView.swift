import NudgeCore
import SwiftUI

/// One request, shared by the expanded pill and the dropdown (layout option B, number first). The whole row is one button that opens the PR
/// (hover and pressed fills; the cursor stays an arrow because macOS ignores cursor changes from an inactive app,
/// which Nudge always is); only the action buttons on the second line are their own targets. Hover (or keyboard focus) swaps the work time for the icon actions, and while the pointer is
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
    @State private var timerHovered = false
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

    /// Option B: `#number` leads the title line; the second line is owner avatar, repo, team, and diff size, with
    /// the work time (or, revealed, the actions) at its end. Tier shows in the row tint and the timer color.
    private var content: some View {
        VStack(spacing: Tokens.Space.rowLines) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "#\(row.pr.number)")
                    .font(Tokens.Typo.rowNumber)
                    .monospacedDigit()
                    .foregroundStyle(isTeam ? Tokens.Palette.secondary : Tokens.Palette.text)
                    .fixedSize()
                title
                    .font(Tokens.Typo.rowTitle)
                    .foregroundStyle(isTeam ? Tokens.Palette.secondary : Tokens.Palette.text)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onHover { textHovered = $0 }
                TimerText(since: row.pr.waitingSince, tier: row.tier, live: live, underlined: timerHovered)
                    .animation(.easeOut(duration: 0.12), value: timerHovered)
                    .onHover(perform: hoverTimer)
                    .anchoredPopover(isPresented: $showBreakdown, arrowEdge: .bottom) {
                        WorkTimePopover(row: row, config: state.settings.workHours, thresholds: state.settings.thresholds)
                    }
            }
            HStack(alignment: .center, spacing: 12) {
                subtitle
                // Only the shown one takes width, so the narrow work time leaves line 2 room for the repo name.
                Group {
                    if revealed { actions } else { WorkChip(seconds: row.workSeconds, tier: row.tier, plain: true) }
                }
                .transition(.opacity)
                .frame(height: IconButtonStyle.height)
                .animation(.easeOut(duration: 0.15), value: revealed)
            }
        }
        .padding(.horizontal, Tokens.Space.rowH)
        .padding(.vertical, Tokens.Space.rowV)
    }

    /// The tracker key, if the title starts with one, in tertiary grey before the rest.
    private var title: Text {
        let parts = row.titleParts
        guard let key = parts.key else { return Text(verbatim: parts.rest) }
        let dimmed = Text(verbatim: "\(key) ").foregroundStyle(Tokens.Palette.tertiary).fontWeight(.semibold)
        return Text("\(dimmed)\(parts.rest)")
    }

    /// Owner avatar, repo, team, diff; or the hovered action button's name in the same spot (0.12s cross-fade).
    private var subtitle: some View {
        let label = actionLabel.text
        return ZStack(alignment: .leading) {
            Text(label ?? "")
                .font(Tokens.Typo.rowSubtitle.weight(.semibold))
                .lineLimit(1)
                .opacity(label == nil ? 0 : 1)
                .accessibilityHidden(label == nil)
            details.opacity(label == nil ? 1 : 0).accessibilityHidden(label != nil)
        }
        .foregroundStyle(Tokens.Palette.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.12), value: label)
        .contentShape(Rectangle())
        .onHover { textHovered = $0 }
    }

    private var details: some View {
        // Under a repository or owner header the row drops what the header already says.
        let grouping = state.settings.groupBy
        return HStack(spacing: 6) {
            if grouping != .repository, grouping != .owner { Avatar(login: row.pr.owner, size: 16) }
            if grouping != .repository {
                Text(verbatim: row.pr.name)
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(-1)
            }
            if case let .team(_, slug) = row.pr.via {
                Label(slug, systemImage: "person.2.fill")
                    .labelStyle(MiniLabelStyle())
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            if let diff = row.pr.diff {
                if grouping != .repository || row.pr.via.isTeam {
                    Text(verbatim: "·").foregroundStyle(Tokens.Palette.tertiary)
                }
                Label(diff.filesLabel, systemImage: "doc")
                    .labelStyle(MiniLabelStyle())
                    .monospacedDigit()
                    .fixedSize()
                // The bar gives way to the action cluster while revealed.
                DiffStatView(diff: diff, showsBar: !revealed)
            }
        }
        .font(Tokens.Typo.rowSubtitle)
    }

    /// Their own click targets inside the row button; no hover card while the pointer is over them.
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
        .onDisappear { actionLabel.text = nil; actionsHovered = false }
        .environment(\.actionLabel, actionLabel)
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
        timerHovered = inside
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

/// The row as a button: `fillHover` while hovered (or active, or with its snooze menu open),
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

/// Icon + title for the 26pt text buttons (hover card, dropdown header).
struct MiniLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}
