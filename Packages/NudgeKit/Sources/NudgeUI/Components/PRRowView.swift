import NudgeCore
import SwiftUI

/// One request, shared by the expanded pill and the dropdown. Two lines; hover (or keyboard focus)
/// cross-fades the work chip into the icon actions. The timer never moves.
struct PRRowView: View {
    let row: PRRow
    let state: NudgeState
    let intents: NudgeIntents
    var live = false
    var isActive = false
    var cardEdge: Edge = .bottom
    @Environment(\.hoverCards) private var cards
    @State private var hovered = false
    @State private var titleHovered = false
    @State private var showSnooze = false
    @State private var showBreakdown = false
    @State private var breakdownTask: Task<Void, Never>?

    private var isTeam: Bool { row.pr.via.isTeam }
    private var revealed: Bool { hovered || isActive || showSnooze }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.rowGap) {
            TierDot(tier: row.tier, isTeam: isTeam, dimmed: state.isOffHours)
                .transition(.symbolEffect(.drawOn))
                .padding(.top, 4)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button { intents.open(row) } label: {
                        Text(row.pr.title)
                            .font(Tokens.Typo.rowTitle)
                            .foregroundStyle(isTeam ? Tokens.Palette.secondary : Tokens.Palette.text)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { titleHovered = $0 }
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityHint("Opens the pull request")
                    TimerText(since: row.pr.waitingSince, tier: row.tier, live: live)
                        .onHover(perform: hoverTimer)
                        .popover(isPresented: $showBreakdown, arrowEdge: .bottom) {
                            WorkTimePopover(row: row, config: state.settings.workHours, thresholds: state.settings.thresholds)
                        }
                }
                HStack(alignment: .center, spacing: 8) {
                    Text(row.subtitle)
                        .font(Tokens.Typo.rowSubtitle)
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onHover { titleHovered = $0 }
                    ZStack(alignment: .trailing) {
                        WorkChip(seconds: row.workSeconds, tier: row.tier).opacity(revealed ? 0 : 1)
                        actions.opacity(revealed ? 1 : 0)
                    }
                    .frame(height: 26)
                    .animation(.easeOut(duration: 0.15), value: revealed)
                }
            }
        }
        .padding(.horizontal, Tokens.Space.rowH)
        .padding(.vertical, Tokens.Space.rowV)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(revealed ? Tokens.Palette.fill : .clear)
                .background(rowTint, in: RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous))
        .onHover { hovered = $0 }
        .hoverCard(row: row, intents: intents, arrowEdge: cardEdge, triggerHovered: titleHovered, rowHovered: hovered)
        .contextMenu {
            RowContextMenu(row: row, state: state, intents: intents,
                           customSnooze: { showSnooze = true }, showDetails: { cards.toggle(row.id) })
        }
        .onChange(of: showSnooze || showBreakdown) { _, open in cards.popoverOpen = open }
        .motion(Motion.crossfade, value: revealed)
        .motion(Motion.tint, value: row.tier)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Start review") { intents.startReview(row, nil) }
        .accessibilityAction(named: "Snooze") { intents.snooze(row, state.settings.defaultSnooze) }
        .accessibilityAction(named: "Hide") { intents.hide(row) }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            SplitIconMenuButton(symbol: "play.fill", label: "Start review", menuLabel: "Run one action", role: .accent) {
                intents.startReview(row, nil)
            } menu: {
                ForEach(state.settings.actions) { action in
                    Button { intents.startReview(row, action.id) } label: { Label(action.name, systemImage: action.symbol) }
                }
                if state.settings.actions.isEmpty { Text("No actions yet") }
            }
            SplitIconPopoverButton(symbol: "moon.zzz", label: "Snooze \(state.settings.defaultSnooze.longLabel)",
                                   menuLabel: "More snooze options", isPresented: $showSnooze) {
                intents.snooze(row, state.settings.defaultSnooze)
            } popover: {
                SnoozeMenu(row: row, state: state, intents: intents) { showSnooze = false }
            }
            IconButton(symbol: "eye.slash", label: "Hide until re-requested") { intents.hide(row) }
            IconButton(symbol: "arrow.up.right", label: "Open on GitHub", role: .secondary) { intents.open(row) }
        }
        .fixedSize()
        .accessibilityHidden(!revealed)
    }

    private var rowTint: Color {
        Tokens.Tier.rowTint(row.tier) ?? .clear
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

struct MiniLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}
