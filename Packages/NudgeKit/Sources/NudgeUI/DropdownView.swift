import NudgeCore
import SwiftUI

/// The status-item panel: header, rows, snoozed group, display mode, Settings and Quit.
public struct DropdownView: View {
    private let state: NudgeState
    private let intents: NudgeIntents
    @State private var activeIndex: Int?
    @State private var snoozedOpen = false
    @State private var cards = HoverCardCoordinator()
    @FocusState private var focused: Bool

    public init(state: NudgeState, intents: NudgeIntents) {
        self.state = state
        self.intents = intents
    }

    private var displayMode: Binding<DisplayMode> {
        Binding(get: { state.settings.displayMode },
                set: { mode in intents.updateSettings { $0.displayMode = mode } })
    }

    public var body: some View {
        VStack(spacing: 2) {
            header
            if state.rows.isEmpty { emptyState } else {
                RowList(state: state, intents: intents, live: true, activeID: activeIndex.map { state.rows[$0].id })
            }
            if !state.snoozedRows.isEmpty { snoozed }
            NoticeLine(notice: state.notice)
            displayModeSection
            menuItems
        }
        .padding(8)
        .frame(width: Tokens.Size.panelWidth)
        .frame(maxHeight: Tokens.Size.panelMaxHeight + 200)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Tokens.Palette.text)
        .glassEffect(.regular, in: .rect(cornerRadius: Tokens.Radius.dropdown, style: .continuous))
        .padding(16)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.return, phases: .down) { press in
            guard let row = activeRow else { return .ignored }
            if press.modifiers.contains(.command) { intents.startReview(row, nil) }
            else if press.modifiers.contains(.option) { cards.toggle(row.id) }
            else { intents.open(row) }
            return .handled
        }
        .onKeyPress(.space) {
            guard let row = activeRow else { return .ignored }
            cards.toggle(row.id)
            return .handled
        }
        .environment(\.hoverCards, cards)
        .onChange(of: state.rows.map(\.id)) { _, ids in
            if let i = activeIndex, i >= ids.count { activeIndex = ids.isEmpty ? nil : ids.count - 1 }
        }
    }

    private var activeRow: PRRow? {
        activeIndex.flatMap { state.rows.indices.contains($0) ? state.rows[$0] : nil }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !state.rows.isEmpty else { return .ignored }
        let next = (activeIndex ?? (delta > 0 ? -1 : state.rows.count)) + delta
        activeIndex = min(max(next, 0), state.rows.count - 1)
        return .handled
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Tokens.Typo.heading)
                    .contentTransition(.numericText())
                    .motion(Motion.roll, value: state.rows.count)
                Text(state.status.syncedLabel).font(Tokens.Typo.caption).foregroundStyle(Tokens.Palette.secondary)
            }
            Spacer()
            Button { intents.syncNow() } label: { Label("Sync", systemImage: "arrow.clockwise") }
                .buttonStyle(MiniButtonStyle())
                .labelStyle(MiniLabelStyle())
                .accessibilityLabel("Sync now")
        }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 8)
        .contentShape(Rectangle())
        .contextMenu { PillContextMenu(state: state, intents: intents, includesOpenDropdown: false) }
    }

    private var title: String {
        switch state.rows.count {
        case 0: state.status == .starting ? "Syncing…" : "Nothing waiting on you"
        case 1: "1 waiting on you"
        case let n: "\(n) waiting on you"
        }
    }

    @ViewBuilder private var emptyState: some View {
        if let problem = state.status.problem {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.Palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.message).font(Tokens.Typo.settingsBody.weight(.semibold))
                    if let fix = problem.fix { Text(fix).font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.secondary) }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Tokens.Palette.fill, in: RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous))
        } else if state.status != .starting {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Tokens.Palette.sparkle)
                Text("All clear").font(Tokens.Typo.rowTitle)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private var snoozed: some View {
        VStack(spacing: 2) {
            Button { withAnimation(Motion.crossfade) { snoozedOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(snoozedOpen ? 90 : 0))
                    Text("Snoozed (\(state.snoozedRows.count))")
                    Spacer()
                    if !snoozedOpen, let back = state.snoozedRows.compactMap(\.snoozedUntil).min() {
                        Text("back at \(Format.weekdayTimeIfNotToday(back))")
                    }
                }
                .font(Tokens.Typo.rowSubtitle.weight(.semibold))
                .foregroundStyle(Tokens.Palette.secondary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            if snoozedOpen {
                ForEach(state.snoozedRows) { row in
                    SnoozedRowView(row: row, state: state, intents: intents)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Show timers").font(Tokens.Typo.caption).foregroundStyle(Tokens.Palette.secondary).padding(.horizontal, 4)
            Segmented(segments: [
                .init(option: DisplayMode.menuBarOnly, title: "Menu bar"),
                .init(option: .widgetAlways, title: "Widget"),
                .init(option: .auto, title: "Auto"),
            ], selection: displayMode)
            .accessibilityLabel("Show timers")
            Text(state.settings.displayMode.hint)
                .font(Tokens.Typo.caption.weight(.medium)).foregroundStyle(Tokens.Palette.secondary)
                .padding(.horizontal, 4)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 4)
        .overlay(alignment: .top) { Divider().overlay(Tokens.Palette.hairline) }
        .padding(.top, 4)
    }

    private var menuItems: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Settings…", shortcut: "⌘,") { intents.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "Quit Nudge", shortcut: "⌘Q") { intents.quit() }
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { Divider().overlay(Tokens.Palette.hairline) }
        .padding(.top, 4)
    }
}

private struct SnoozedRowView: View {
    let row: PRRow
    let state: NudgeState
    let intents: NudgeIntents
    @Environment(\.hoverCards) private var cards
    @State private var hovered = false
    @State private var titleHovered = false
    @State private var showSnooze = false

    var body: some View {
        HStack(spacing: Tokens.Space.rowGap) {
            TierDot(tier: row.tier, isTeam: row.pr.via.isTeam, dimmed: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.pr.title).font(Tokens.Typo.rowTitle).foregroundStyle(Tokens.Palette.secondary).lineLimit(1)
                Text(row.snoozedUntil.map { "back at \(Format.weekdayTimeIfNotToday($0))" } ?? row.subtitle)
                    .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { titleHovered = $0 }
            IconButton(symbol: "moon.slash", label: "Unsnooze") { intents.unsnooze(row) }
                .popover(isPresented: $showSnooze, arrowEdge: .bottom) {
                    SnoozeMenu(row: row, state: state, intents: intents) { showSnooze = false }
                }
        }
        .padding(.horizontal, Tokens.Space.rowH).padding(.vertical, Tokens.Space.rowV)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .hoverCard(row: row, intents: intents, arrowEdge: .bottom, triggerHovered: titleHovered, rowHovered: hovered)
        .contextMenu {
            RowContextMenu(row: row, state: state, intents: intents, isSnoozed: true,
                           customSnooze: { showSnooze = true }, showDetails: { cards.toggle(row.id) })
        }
        .onChange(of: showSnooze) { _, open in cards.popoverOpen = open }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.secondary)
            }
        }
        .buttonStyle(MenuItemStyle())
        .frame(height: 30)
    }
}

extension DisplayMode {
    var title: String {
        switch self {
        case .menuBarOnly: "Menu bar"
        case .widgetAlways: "Widget"
        case .auto: "Auto"
        }
    }

    var hint: String {
        switch self {
        case .menuBarOnly: "Timers live in the menu bar only."
        case .widgetAlways: "The floating pill stays on screen, even when nothing is waiting."
        case .auto: "Auto shows the floating pill while anything is waiting."
        }
    }
}
