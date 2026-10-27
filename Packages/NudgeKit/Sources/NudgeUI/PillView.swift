import NudgeCore
import SwiftUI

/// The floating widget: a tier-tinted glass capsule that morphs into the request list when `state.pillExpanded`.
public struct PillView: View {
    private let state: NudgeState
    private let intents: NudgeIntents
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zero: ZeroPhase = .idle
    @State private var cards = HoverCardCoordinator()

    private enum ZeroPhase { case idle, sparkle, settled }

    public init(state: NudgeState, intents: NudgeIntents) {
        self.state = state
        self.intents = intents
    }

    private var oldestTier: Tier? { state.oldest?.tier }
    private var hasRows: Bool { !state.rows.isEmpty }
    private var expanded: Bool { state.pillExpanded && hasRows }

    public var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: horizontalAlignment, spacing: 8) {
                if state.pillEdge == .bottom { staleChip }
                if expanded {
                    expandedList
                        .glassEffect(.regular.tint(Tokens.Tier.tint(oldestTier)),
                                     in: .rect(cornerRadius: Tokens.Radius.panel, style: .continuous))
                        .glassEffectID("pill", in: glass)
                } else {
                    collapsed
                        .glassEffect(.regular.tint(Tokens.Tier.tint(oldestTier)).interactive(), in: .capsule)
                        .glassEffectID("pill", in: glass)
                }
                if state.pillEdge != .bottom { staleChip }
            }
        }
        .modifier(BounceOnce(trigger: reduceMotion ? 0 : state.newRequestPulse))
        .scaleEffect(zero == .settled && state.settings.displayMode != .widgetAlways ? 0.2 : 1)
        .opacity(state.pillDimmed ? 0.6 : (zero == .settled && state.settings.displayMode != .widgetAlways ? 0 : 1))
        .motion(Motion.dim, value: state.pillDimmed)
        .motion(Motion.shrink, value: zero)
        .animation(Motion.pick(Motion.morph, reduced: reduceMotion), value: expanded)
        .motion(Motion.tint, value: oldestTier)
        .onChange(of: hasRows, initial: true) { _, has in has ? reset() : celebrate() }
        .environment(\.hoverCards, cards)
        .padding(16)
    }

    // MARK: Collapsed

    @ViewBuilder private var collapsed: some View {
        Group {
            if let oldest = state.oldest {
                countCapsule(oldest)
            } else if let problem = state.status.problem, problem.fix != nil || state.status.lastSync == nil {
                problemCapsule(problem)
            } else if case .starting = state.status {
                capsule { Image(systemName: "clock.badge").font(.system(size: 14, weight: .semibold)); Text("Syncing…").font(Tokens.Typo.pillLabel) }
                    .foregroundStyle(Tokens.Palette.secondary)
            } else if zero == .sparkle || state.settings.displayMode != .widgetAlways {
                allClear
            } else {
                checkCapsule
            }
        }
        .foregroundStyle(Tokens.Palette.text)
    }

    private func countCapsule(_ oldest: PRRow) -> some View {
        capsule {
            TierDot(tier: oldest.tier, isTeam: oldest.pr.via.isTeam, dimmed: state.isOffHours)
            Text(verbatim: "\(state.rows.count)")
                .font(Tokens.Typo.pillCount).monospacedDigit()
                .contentTransition(.numericText())
                .motion(Motion.roll, value: state.rows.count)
            Text("·").font(Tokens.Typo.pillLabel).foregroundStyle(Tokens.Palette.secondary)
            TimerText(since: oldest.pr.waitingSince, tier: oldest.tier, font: Tokens.Typo.pillTimer, tracking: -0.42)
                .opacity(state.status.problem == nil ? 1 : 0.7)
            if state.isOffHours {
                MoonChip().transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .motion(Motion.chip, value: state.isOffHours)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collapsedLabel(oldest))
        .contextMenu { PillContextMenu(state: state, intents: intents) }
    }

    private func problemCapsule(_ problem: SyncProblem) -> some View {
        capsule {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tokens.Palette.warning)
            Text(problem.fix ?? problem.message).font(Tokens.Typo.pillLabel)
        }
        .accessibilityLabel("Needs attention. \(problem.message) \(problem.fix ?? "")")
    }

    private var allClear: some View {
        capsule {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Tokens.Palette.sparkle)
                .symbolEffect(.bounce, options: reduceMotion ? .nonRepeating.speed(0) : .nonRepeating, value: zero)
            Text("All clear").font(Tokens.Typo.pillCount)
        }
        .accessibilityLabel("All clear")
    }

    private var checkCapsule: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Tokens.Palette.check)
            .frame(width: 38, height: 38)
            .accessibilityLabel("Nothing waiting")
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .padding(.leading, 15).padding(.trailing, 18)
            .frame(height: Tokens.Size.pillHeight)
            .fixedSize()
    }

    @ViewBuilder private var staleChip: some View {
        if case let .stale(lastSync?, problem) = state.status, problem.fix == nil, hasRows {
            Text("stale · synced \(Format.ago(lastSync))")
                .font(Tokens.Typo.caption)
                .foregroundStyle(Tokens.Palette.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .transition(.opacity)
        }
    }

    // MARK: Expanded

    private var expandedList: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("Waiting on you").font(Tokens.Typo.pillLabel)
                Text(verbatim: "\(state.rows.count)")
                    .font(Tokens.Typo.chip).monospacedDigit()
                    .foregroundStyle(Tokens.Palette.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Tokens.Palette.fill, in: Capsule())
                    .contentTransition(.numericText(countsDown: true))
                    .motion(Motion.roll, value: state.rows.count)
                Spacer()
                IconButton(symbol: "arrow.clockwise", label: "Sync now", role: .secondary) { intents.syncNow() }
                IconButton(symbol: "gearshape", label: "Settings", role: .secondary) { intents.openSettings() }
            }
            .padding(.leading, Tokens.Space.rowH).padding(.trailing, 4).padding(.top, 2).padding(.bottom, 6)
            .foregroundStyle(Tokens.Palette.text)
            .contentShape(Rectangle())
            .contextMenu { PillContextMenu(state: state, intents: intents) }

            RowList(state: state, intents: intents, live: true, cardEdge: state.pillEdge.cardArrowEdge)

            if !state.snoozedRows.isEmpty { snoozedLine }
            NoticeLine(notice: state.notice)

            HStack(spacing: 4) {
                if let problem = state.status.problem {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Tokens.Palette.warning)
                    Text(problem.fix ?? problem.message).foregroundStyle(Tokens.Palette.warning)
                    Text("·")
                }
                Text(state.status.syncedLabel)
                if state.resultsCapped {
                    Text("· 200+ results, some may be missing").foregroundStyle(Tokens.Palette.warning)
                }
                Spacer()
            }
            .font(Tokens.Typo.caption)
            .foregroundStyle(Tokens.Palette.secondary)
            .lineLimit(1)
            .padding(.horizontal, Tokens.Space.rowH).padding(.top, 8).padding(.bottom, 2)
            .overlay(alignment: .top) { Divider().overlay(Tokens.Palette.hairline).padding(.horizontal, 4) }
            .padding(.top, 4)
            .contentShape(Rectangle())
            .contextMenu { PillContextMenu(state: state, intents: intents) }
        }
        .padding(Tokens.Space.panelInset)
        .frame(width: Tokens.Size.panelWidth)
        .frame(maxHeight: Tokens.Size.panelMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var snoozedLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.fill").font(.system(size: 10, weight: .bold))
            Text("Snoozed (\(state.snoozedRows.count))")
            Spacer()
            if let back = state.snoozedRows.compactMap(\.snoozedUntil).min() {
                Text("back at \(Format.weekdayTimeIfNotToday(back))").foregroundStyle(Tokens.Palette.secondary)
            }
        }
        .font(Tokens.Typo.chip)
        .foregroundStyle(Tokens.Palette.text)
        .padding(.horizontal, Tokens.Space.rowH).padding(.vertical, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Helpers

    private var horizontalAlignment: HorizontalAlignment {
        state.pillEdge == .left ? .leading : .trailing
    }

    private func collapsedLabel(_ oldest: PRRow) -> String {
        var label = "\(state.rows.count) waiting on you"
        if let since = oldest.pr.waitingSince {
            label += ", oldest \(Format.spoken(Date.now.timeIntervalSince(since)))"
        }
        if state.isOffHours { label += ", outside work hours" }
        return label
    }

    private func reset() { zero = .idle }

    private func celebrate() {
        guard state.status.problem == nil else { return }
        zero = .sparkle
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if zero == .sparkle { zero = .settled }
        }
    }
}

/// The scrolling list of rows with slide-in/out transitions, shared by the pill and the dropdown.
struct RowList: View {
    let state: NudgeState
    let intents: NudgeIntents
    var live: Bool
    var cardEdge: Edge = .bottom
    var activeID: String? = nil
    @Environment(\.hoverCards) private var cards

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(state.rows) { row in
                    PRRowView(row: row, state: state, intents: intents, live: live, isActive: row.id == activeID, cardEdge: cardEdge)
                        .id(row.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .motion(Motion.rowSlide, value: state.rows.map(\.id))
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollPhaseChange { _, phase in cards.scrolling = phase != .idle }
        .onAppear { cards.activate() }
    }
}

/// One vertical hop per change of `trigger`.
private struct BounceOnce: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger, content: { view, y in
            view.offset(y: y)
        }, keyframes: { _ in
            KeyframeTrack(content: {
                CubicKeyframe(-12, duration: 0.14)
                SpringKeyframe(0, duration: 0.3, spring: .bouncy)
            })
        })
    }
}
