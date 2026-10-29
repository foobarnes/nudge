import NudgeCore
import SwiftUI

// Small shared pieces: the 26pt "mini" button, split buttons, chips.

struct MiniButtonStyle: ButtonStyle {
    enum Role { case normal, primary, plain }
    var role: Role = .normal
    var leading = true
    var trailing = true
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typo.button)
            .foregroundStyle(role == .primary ? .white : Tokens.Palette.text)
            .padding(.horizontal, role == .plain ? 4 : 9)
            .frame(height: Tokens.Size.buttonHeight)
            .background(fill(pressed: configuration.isPressed), in: shape)
            .contentShape(shape)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private var shape: UnevenRoundedRectangle {
        let r = Tokens.Radius.button
        return UnevenRoundedRectangle(topLeadingRadius: leading ? r : 0, bottomLeadingRadius: leading ? r : 0,
                                      bottomTrailingRadius: trailing ? r : 0, topTrailingRadius: trailing ? r : 0)
    }

    private func fill(pressed: Bool) -> Color {
        switch role {
        case .primary: pressed || hovered ? Tokens.Palette.accentPressed : Tokens.Palette.accent
        case .normal: pressed ? Tokens.Palette.fillStrong : hovered ? Tokens.Palette.fillHover : Tokens.Palette.fill
        case .plain: pressed || hovered ? Tokens.Palette.fill : .clear
        }
    }
}

/// Left half performs the primary action; the ⌄ opens `menu`.
struct SplitButton<Label: View, MenuContent: View>: View {
    var role: MiniButtonStyle.Role = .normal
    let action: () -> Void
    @ViewBuilder let label: Label
    @ViewBuilder let menu: MenuContent

    var body: some View {
        HStack(spacing: 1) {
            Button(action: action) { label }
                .buttonStyle(MiniButtonStyle(role: role, trailing: false))
            Menu { menu } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 7)
                    .frame(height: Tokens.Size.buttonHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(MiniButtonStyle(role: role, leading: false))
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// Like `SplitButton`, but the ⌄ presents `popover` (for content a menu can't hold, like a text field).
struct SplitPopoverButton<Label: View, Popover: View>: View {
    var role: MiniButtonStyle.Role = .normal
    @Binding var isPresented: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @ViewBuilder let popover: Popover

    var body: some View {
        HStack(spacing: 1) {
            Button(action: action) { label }
                .buttonStyle(MiniButtonStyle(role: role, trailing: false))
            Button { isPresented.toggle() } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).padding(.horizontal, -2)
            }
            .buttonStyle(MiniButtonStyle(role: role, leading: false))
            .accessibilityLabel("More options")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { popover }
        }
    }
}

struct Chip: View {
    let symbol: String
    let text: String
    var fill: Color = Tokens.Palette.fill
    var color: Color = Tokens.Palette.secondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).font(Tokens.Typo.chip).monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(fill, in: RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous))
        .fixedSize()
    }
}

struct WorkChip: View {
    let seconds: TimeInterval?
    let tier: Tier

    var body: some View {
        Chip(symbol: "briefcase.fill", text: "\(DurationFormat.compact(seconds ?? 0)) work",
             fill: Tokens.Tier.chipFill(tier), color: tier == .fresh ? Tokens.Palette.secondary : Tokens.Tier.text(tier))
            .accessibilityLabel("\(Format.spoken(seconds ?? 0)) of work time")
    }
}

/// Non-fatal sync notice ("Authorize SSO for acme" + `gh auth refresh`) under the list.
struct NoticeLine: View {
    let notice: SyncProblem?

    var body: some View {
        if let notice {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.system(size: 10, weight: .bold))
                Text(notice.message)
                if let fix = notice.fix {
                    Text(fix).font(Tokens.Typo.codeSmall)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Tokens.Palette.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .font(Tokens.Typo.caption)
            .foregroundStyle(Tokens.Palette.warning)
            .lineLimit(1)
            .padding(.horizontal, Tokens.Space.rowH).padding(.vertical, 6)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Small brand-violet dot beside "Synced 2m ago" while sync is healthy; absent when starting or stale.
struct SyncedDot: View {
    let status: SyncStatus

    var body: some View {
        if case .ok = status {
            Circle().fill(Tokens.Palette.accentGlyph).frame(width: 5, height: 5).accessibilityHidden(true)
        }
    }
}

/// "Synced 12s ago", re-rendered every second so the age keeps counting between syncs.
struct SyncedLabel: View {
    let status: SyncStatus

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(status.syncedLabel(at: context.date))
        }
    }
}

struct MoonChip: View {
    var body: some View {
        Chip(symbol: "moon.fill", text: "off hours")
            .accessibilityLabel("Outside work hours")
    }
}

/// Filled dot for direct requests, hollow ring for team requests. SF Symbols so symbol effects apply.
struct TierDot: View {
    let tier: Tier
    let isTeam: Bool
    var dimmed = false
    var size: CGFloat = Tokens.Size.dot

    var body: some View {
        Image(systemName: isTeam ? "circle" : "circle.fill")
            .font(.system(size: size, weight: isTeam ? .heavy : .regular))
            .foregroundStyle(Tokens.Tier.dot(tier))
            .background {
                if tier == .red, !isTeam {
                    Circle().fill(Tokens.Tier.dot(.red).opacity(0.18)).padding(-3)
                }
            }
            .symbolEffect(.wiggle, value: tier)
            .opacity(dimmed ? 0.45 : 1)
            .motion(Motion.tint, value: tier)
            .motion(Motion.dim, value: dimmed)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The hero number. Wall-clock waiting time: compact at rest, `H:MM:SS` while `live`.
struct TimerText: View {
    let since: Date?
    let tier: Tier
    var live = false
    var font: Font = Tokens.Typo.rowTimer
    var tracking: CGFloat = -0.36
    /// Stale sync: keeps counting in the secondary color (States board).
    var greyed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: live ? 1 : 60)) { context in
            Text(label(at: context.date))
        }
        .font(font)
        .monospacedDigit()
        .tracking(tracking)
        .foregroundStyle(greyed ? Tokens.Palette.secondary : Tokens.Tier.text(tier))
        .shadow(color: Tokens.Palette.textShadow, radius: 1.5, y: 0.5)
        .contentTransition(.numericText())
        .motion(Motion.roll, value: live)
        .motion(Motion.tint, value: tier)
        .help(since == nil ? "Request time unknown" : "")
    }

    private func label(at date: Date) -> String {
        guard let since else { return "—" }
        let seconds = date.timeIntervalSince(since)
        return live ? DurationFormat.clock(seconds) : DurationFormat.compact(seconds)
    }
}

enum Format {
    static func clockTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func weekdayTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func weekdayTimeIfNotToday(_ date: Date, now: Date = .now) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? clockTime(date) : weekdayTime(date)
    }

    static func ago(_ date: Date, now: Date = .now) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }

    /// "4 hours 12 minutes", for accessibility labels.
    static func spoken(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d) day\(d == 1 ? "" : "s")") }
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 || parts.isEmpty { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }
}

extension PRRow {
    var subtitle: String {
        var text = "\(pr.repo) #\(pr.number) · \(pr.author)"
        if case let .team(_, slug) = pr.via { text += " · team \(slug)" }
        return text
    }

    var accessibilityLabel: String {
        var label = "\(pr.repo) \(pr.number), \(pr.title)"
        if let since = pr.waitingSince {
            label += ", waiting \(Format.spoken(Date.now.timeIntervalSince(since)))"
        }
        if case let .team(_, slug) = pr.via { label += ", team \(slug)" }
        return label
    }
}

extension SyncStatus {
    var lastSync: Date? {
        switch self {
        case .starting: nil
        case let .ok(lastSync): lastSync
        case let .stale(lastSync, _): lastSync
        }
    }

    var problem: SyncProblem? {
        if case let .stale(_, problem) = self { problem } else { nil }
    }

    func syncedLabel(at now: Date = .now) -> String {
        switch self {
        case .starting: "Syncing…"
        case let .ok(lastSync): "Synced \(Format.ago(lastSync, now: now))"
        case let .stale(lastSync, _): lastSync.map { "Stale · synced \(Format.ago($0, now: now))" } ?? "Not synced yet"
        }
    }
}
