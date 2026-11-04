import NudgeCore
import SwiftUI

/// Natural sizes of the pill in both states, so the shell can size its window before and after a morph.
public struct PillSizes: Equatable, Sendable {
    public var collapsed: CGSize = .zero
    public var expanded: CGSize = .zero
    public init() {}
}

public struct PillSizesKey: PreferenceKey {
    public static let defaultValue = PillSizes()
    public static func reduce(value: inout PillSizes, nextValue: () -> PillSizes) { value = nextValue() }
}

extension EnvironmentValues {
    /// Multiplies every morph duration (the gallery slows the morph down to inspect frames).
    @Entry public var pillMotionScale: Double = 1
}

/// The floating widget: one glass shape, pinned to its anchored corner, whose size and corner radius morph
/// between a capsule and the request card. Both contents are laid out at their final size and revealed
/// through the clip, so nothing reflows mid-morph.
public struct PillView: View {
    private let state: NudgeState
    private let intents: NudgeIntents
    private let anchor: Alignment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pillMotionScale) private var motionScale
    /// The all-clear has played out: the pill has left, or (widget always) settled on the check.
    @State private var settled = false
    @State private var sparkle = 0
    /// New-request cues: one jiggle, hop (jiggle off), or glow per increment.
    @State private var jiggles = 0
    @State private var hops = 0
    @State private var glows = 0
    @State private var cards = HoverCardCoordinator()
    @State private var collapsedSize = CGSize.zero
    @State private var expandedSize = CGSize.zero
    @State private var chipHeight: CGFloat = 0

    /// `anchor` is the screen corner the pill is pinned to; the shape grows away from it in both axes.
    public init(state: NudgeState, intents: NudgeIntents, anchor: Alignment = .topTrailing) {
        self.state = state
        self.intents = intents
        self.anchor = anchor
    }

    /// Seconds from `pillExpanded = false` until the collapse morph has finished (the shell shrinks its window then).
    public static func collapseDuration(reduceMotion: Bool) -> Double { MorphTiming.collapseDuration(reduced: reduceMotion) }

    /// Seconds from the last request leaving until the all-clear has played out (the shell hides the pill then).
    public static func allClearDuration(fromCard: Bool, reduceMotion: Bool) -> Double {
        AllClearTiming(fromCard: fromCard, reduced: reduceMotion).total
    }

    private var oldestTier: Tier? { state.oldest?.tier }
    private var hasRows: Bool { !state.rows.isEmpty }
    private var expanded: Bool { state.pillExpanded && hasRows }
    private var anchoredAtBottom: Bool { anchor.vertical == .bottom }
    private var hiddenAtZero: Bool { settled && state.settings.displayMode != .widgetAlways }
    private var isNew: Bool { state.hasNewRows }

    public var body: some View {
        // The outer frame never animates: it is always the larger (card) size, with the morphing shape pinned to
        // the anchor corner inside it. If the parent laid out the animating frame, it would place it at its final
        // size and the shape would grow away from the wrong edge.
        ZStack(alignment: anchor) {
            morph
            staleChip.offset(y: (collapsedSize.height + 8) * (anchoredAtBottom ? -1 : 1))
        }
        .frame(width: outerSize.width, height: outerSize.height, alignment: anchor)
        .preference(key: PillSizesKey.self, value: sizes)
        .modifier(BounceOnce(trigger: hops))
        .modifier(Jiggle(trigger: jiggles))
        .scaleEffect(hiddenAtZero && !reduceMotion ? 0.85 : 1, anchor: anchor.unitPoint)
        .opacity(hiddenAtZero ? 0 : state.pillDimmed ? 0.75 : 1)
        .motion(Motion.dim, value: state.pillDimmed)
        .motion(Motion.shrink, value: settled)
        .task(id: hasRows) { if hasRows { settled = false } else { await celebrate() } }
        .onChange(of: state.newRequestPulse) { cue(reminder: false) }
        .onChange(of: state.reminderPulse) { cue(reminder: true) }
        .environment(\.hoverCards, cards)
    }

    /// The card's largest size, so a shape still collapsing from a card whose rows just left never overflows it.
    private var outerSize: CGSize {
        let s = sizes
        return CGSize(width: max(s.collapsed.width, Tokens.Size.panelWidth),
                      height: max(s.collapsed.height, Tokens.Size.panelMaxHeight))
    }

    private var sizes: PillSizes {
        var s = PillSizes()
        s.collapsed = collapsedSize
        if chipHeight > 0 { s.collapsed.height += chipHeight + 8 }
        s.expanded = hasRows ? expandedSize : collapsedSize
        return s
    }

    // MARK: Morph

    private var timing: MorphTiming { MorphTiming(reduced: reduceMotion, scale: motionScale) }

    private var morph: some View {
        let size = expanded ? expandedSize : collapsedSize
        let radius = expanded ? Tokens.Radius.panel : collapsedSize.height / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack(alignment: anchor) {
            // The glass is a leaf whose size and radius animate; the ZStack's alignment keeps its anchor corner
            // put. Nothing inside it moves, so the content can't drift against it.
            Color.clear
                .frame(width: size.width, height: size.height)
                .background {
                    // Tint we control, so it reads the same whether the panel is key or not. Capsule only
                    // (concept B): it fades out as the shape opens into the neutral card.
                    shape.fill(Tokens.Palette.glassScrim)
                    if let tint = Tokens.Tier.tint(oldestTier, new: isNew) {
                        shape.fill(tint).opacity(expanded ? 0 : 1)
                    }
                    shape.fill(Tokens.Palette.accentGlyph).modifier(Glow(trigger: glows)).opacity(expanded ? 0 : 1)
                }
                .glassEffect(.regular, in: shape)
                .animation(timing.shape(expanded), value: expanded)
                .animation(timing.resize, value: collapsedSize)
                .motion(Motion.tint, value: oldestTier)
                .motion(Motion.tint, value: isNew)

            // Both contents, laid out at their final size at the anchor corner, revealed through the same shape.
            // The card stays mounted with no rows, so reviewing the last one fades it out like any other collapse.
            ZStack(alignment: anchor) {
                expandedList
                    .opacity(expanded ? 1 : 0)
                    .animation(timing.card(expanded), value: expanded)
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { expandedSize = $0 }
                collapsed
                    .opacity(expanded ? 0 : 1)
                    .scaleEffect(expanded && !reduceMotion ? 0.96 : 1, anchor: anchor.unitPoint)
                    .animation(timing.capsuleContent(expanded), value: expanded)
                    .allowsHitTesting(!expanded)
                    .accessibilityHidden(expanded)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { collapsedSize = $0 }
            }
            .mask(alignment: anchor) {
                shape.frame(width: size.width, height: size.height)
                    .animation(timing.shape(expanded), value: expanded)
                    .animation(timing.resize, value: collapsedSize)
            }
        }
    }

    // MARK: Collapsed

    /// A ZStack, not a Group: the morph's opacity must land on one persistent view, not on whichever capsule is current.
    private var collapsed: some View {
        ZStack(alignment: anchor) {
            Group {
                if let oldest = state.oldest {
                    countCapsule(oldest)
                } else if let problem = state.status.problem, problem.fix != nil || state.status.lastSync == nil {
                    problemCapsule(problem)
                } else if case .starting = state.status {
                    capsule { Image(systemName: "clock.badge").font(.system(size: 14, weight: .semibold)); Text("Syncing…").font(Tokens.Typo.pillLabel) }
                        .foregroundStyle(Tokens.Palette.secondary)
                } else if !settled || state.settings.displayMode != .widgetAlways {
                    allClear
                } else {
                    checkCapsule
                }
            }
            .transition(Self.capsuleSwap)
        }
        .foregroundStyle(Tokens.Palette.text)
    }

    /// One capsule hands over to the next (a count to "All clear", "All clear" to the check): the old one clears out
    /// before the new one fades in, so their labels never overlap.
    private static let capsuleSwap = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
        removal: .opacity.animation(.easeIn(duration: 0.12)))

    private func countCapsule(_ oldest: PRRow) -> some View {
        let stale = state.status.problem != nil
        return capsule {
            TierDot(tier: oldest.tier, isTeam: oldest.pr.via.isTeam, dimmed: state.isOffHours || stale)
            // A count badge, solid violet while a request is new. Same padding either way, so nothing resizes.
            Text(verbatim: "\(state.rows.count)")
                .font(Tokens.Typo.pillCount).monospacedDigit()
                .foregroundStyle(isNew ? Color.white : Tokens.Palette.text)
                .shadow(color: isNew ? .clear : Tokens.Palette.textShadow, radius: 1.5, y: 0.5)
                .contentTransition(.numericText())
                .motion(Motion.roll, value: state.rows.count)
                .padding(.horizontal, 7)
                .frame(minWidth: 26, minHeight: 25)
                .background(isNew ? Tokens.Palette.accent : Tokens.Palette.fill, in: Capsule())
                .motion(Motion.tint, value: isNew)
            Text("·").font(Tokens.Typo.pillLabel).foregroundStyle(Tokens.Palette.secondary)
            TimerText(since: oldest.pr.waitingSince, tier: oldest.tier, font: Tokens.Typo.pillTimer, tracking: -0.42,
                      greyed: stale)
            if state.isOffHours {
                MoonChip().transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .motion(Motion.chip, value: state.isOffHours)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collapsedLabel(oldest))
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
                .foregroundStyle(Tokens.Palette.accentGlyph)
                .symbolEffect(.bounce, options: reduceMotion ? .nonRepeating.speed(0) : .nonRepeating, value: sparkle)
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

    /// Offline note under (or over) the capsule; the open card shows the same status in its footer.
    @ViewBuilder private var staleChip: some View {
        if case let .stale(lastSync?, problem) = state.status, problem.fix == nil, hasRows, !expanded {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("stale · synced \(Format.ago(lastSync, now: context.date))")
            }
                .font(Tokens.Typo.caption)
                .foregroundStyle(Tokens.Palette.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chipHeight = $0 }
                .onDisappear { chipHeight = 0 }
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

            RowList(state: state, intents: intents, live: expanded, cardEdge: state.pillEdge.cardArrowEdge,
                    reveal: RowList.Reveal(shown: expanded, fromBottom: anchoredAtBottom, animation: timing.row))

            if !state.snoozedRows.isEmpty { snoozedLine }
            NoticeLine(notice: state.notice)

            HStack(spacing: 4) {
                if let problem = state.status.problem {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Tokens.Palette.warning)
                    Text(problem.fix ?? problem.message).foregroundStyle(Tokens.Palette.warning)
                    Text("·")
                }
                SyncedDot(status: state.status)
                SyncedLabel(status: state.status)
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

    private func collapsedLabel(_ oldest: PRRow) -> String {
        var label = "\(state.rows.count) waiting on you"
        if let since = oldest.pr.waitingSince {
            label += ", oldest \(Format.spoken(Date.now.timeIntervalSince(since)))"
        }
        if state.isOffHours { label += ", outside work hours" }
        if isNew { label += ", new request" }
        return label
    }

    /// A request arrived, or the shell's reminder fired while one goes unopened: jiggle and glow, glow alone under
    /// Reduce Motion. With jiggle off, arrivals keep the plain hop. The open card doesn't jiggle: it's being read.
    private func cue(reminder: Bool) {
        guard hasRows else { return }
        guard state.settings.jiggleOnNewRequests else {
            if !reminder, !reduceMotion { hops += 1 }
            return
        }
        guard !expanded else { return }
        if !reduceMotion { jiggles += 1 }
        glows += 1
    }

    /// The last request left: the card (if open) collapses onto "All clear", the sparkles bounce once it has landed,
    /// it holds, then the pill leaves (or settles on the check). Cancelled by a request arriving.
    private func celebrate() async {
        // Stale data isn't worth celebrating: go straight to the quiet state.
        guard state.status.problem == nil else { settled = true; return }
        let beat = AllClearTiming(fromCard: state.pillExpanded, reduced: reduceMotion, scale: motionScale)
        try? await Task.sleep(for: .seconds(beat.lead))
        guard !Task.isCancelled else { return }
        sparkle += 1
        try? await Task.sleep(for: .seconds(beat.hold))
        guard !Task.isCancelled else { return }
        settled = true
    }
}

/// The all-clear's beats: the collapse onto the capsule (when the card was open), the hold on "All clear", and the
/// exit (`Motion.shrink`). The shell hides the window once `total` has passed.
struct AllClearTiming {
    let lead: Double
    let hold: Double
    let total: Double

    init(fromCard: Bool, reduced: Bool, scale: Double = 1) {
        lead = (fromCard ? MorphTiming.collapseDuration(reduced: reduced) : 0.3) * scale
        hold = 1.2 * scale
        total = lead + hold + 0.35 * scale
    }
}

/// Choreography of one morph, from the Motion board (`morph`, `pillout`, `listin` keyframes on a 5s cycle):
/// expand runs ~0.75s with a slight overshoot; the capsule content fades out over the first 0.3s and the list
/// fades in from 0.35s. Collapse: the list fades out first, the shape springs back 0.15s later, and the capsule
/// content returns for the last 0.4s. Reduce Motion: plain 0.2s crossfades, no spring.
struct MorphTiming {
    let reduced: Bool
    let scale: Double

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let collapseLead = 0.15

    /// How long the shell should wait after a collapse before shrinking the window.
    static func collapseDuration(reduced: Bool) -> Double { reduced ? 0.25 : collapseLead + 0.9 }

    func shape(_ expanding: Bool) -> Animation {
        if reduced { return crossfade }
        return scaled(expanding ? Self.spring : Self.spring.delay(Self.collapseLead))
    }

    /// The capsule changing width under the pill (a count growing, "All clear" replacing it), mid-morph or not.
    var resize: Animation { reduced ? crossfade : scaled(Self.spring) }

    func capsuleContent(_ expanding: Bool) -> Animation {
        if reduced { return crossfade }
        return scaled(expanding ? .easeOut(duration: 0.3).delay(0.05)
                                : .easeOut(duration: 0.4).delay(Self.collapseLead + 0.45))
    }

    func card(_ expanding: Bool) -> Animation {
        if reduced { return crossfade }
        return scaled(expanding ? .easeInOut(duration: 0.45).delay(0.35) : .easeOut(duration: 0.4))
    }

    func row(_ index: Int, _ expanding: Bool) -> Animation {
        if reduced { return crossfade }
        return scaled(expanding ? .easeOut(duration: 0.4).delay(0.35 + 0.025 * Double(index))
                                : .easeOut(duration: 0.4))
    }

    private var crossfade: Animation { scaled(.easeInOut(duration: 0.2)) }

    /// Slowed by `scale` (the gallery's frame inspection).
    private func scaled(_ animation: Animation) -> Animation { scale == 1 ? animation : animation.speed(1 / scale) }
}

extension Alignment {
    var unitPoint: UnitPoint {
        switch (vertical, horizontal) {
        case (.top, .leading): .topLeading
        case (.top, _): .topTrailing
        case (_, .leading): .bottomLeading
        default: .bottomTrailing
        }
    }
}

/// The scrolling list of rows with slide-in/out transitions, shared by the pill and the dropdown.
struct RowList: View {
    /// Pill-only: rows fade and slide 6pt from the anchor side, staggered, as the card opens.
    struct Reveal {
        var shown: Bool
        var fromBottom: Bool
        var animation: (Int, Bool) -> Animation
    }

    let state: NudgeState
    let intents: NudgeIntents
    var live: Bool
    var cardEdge: Edge = .bottom
    var activeID: String? = nil
    var reveal: Reveal? = nil
    @Environment(\.hoverCards) private var cards
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                    PRRowView(row: row, state: state, intents: intents, live: live, isActive: row.id == activeID, cardEdge: cardEdge)
                        .id(row.id)
                        .opacity(reveal?.shown == false ? 0 : 1)
                        .offset(y: rowOffset)
                        .animation(reveal.map { $0.animation(index, $0.shown) }, value: reveal?.shown)
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

    private var rowOffset: CGFloat {
        guard let reveal, !reveal.shown, !reduceMotion else { return 0 }
        return reveal.fromBottom ? 6 : -6
    }
}

/// One damped shake per change of `trigger`: a single linear clock drives `Motion.jiggleOffset`, so the motion is
/// one continuous curve rather than chained keyframes.
private struct Jiggle: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Motion.jiggleDuration, trigger: trigger, content: { view, t in
            view.offset(x: Motion.jiggleOffset(t))
        }, keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0)
                LinearKeyframe(Motion.jiggleDuration, duration: Motion.jiggleDuration)
            }
        })
    }
}

/// One violet wash per change of `trigger` (opacity only, so it plays under Reduce Motion too).
private struct Glow: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger, content: { view, opacity in
            view.opacity(opacity)
        }, keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(Motion.glowPeak, duration: Motion.glowRise)
                LinearKeyframe(Motion.glowPeak, duration: Motion.glowHold)
                CubicKeyframe(0, duration: Motion.glowFade)
            }
        })
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
