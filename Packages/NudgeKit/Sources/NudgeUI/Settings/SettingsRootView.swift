import NudgeCore
import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, notifications, actions, about
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .notifications: "Notifications"
        case .actions: "Actions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .actions: "play"
        case .about: "info.circle"
        }
    }
}

/// Frameless dark-glass settings window content with an inset floating sidebar.
/// The shell hosts it in a transparent, full-size-content window; the traffic lights sit in the sidebar's top inset.
public struct SettingsRootView: View {
    private let state: NudgeState
    private let intents: NudgeIntents
    @State private var tab: SettingsTab

    public init(state: NudgeState, intents: NudgeIntents) {
        self.init(state: state, intents: intents, initialTab: .general)
    }

    public init(state: NudgeState, intents: NudgeIntents, initialTab: SettingsTab) {
        self.state = state
        self.intents = intents
        _tab = State(initialValue: initialTab)
    }

    public var body: some View {
        HStack(spacing: 14) {
            sidebar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 18).padding(.trailing, 18).padding(.bottom, 18)
        }
        .padding(12)
        .frame(minWidth: 960, minHeight: 620)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Tokens.Palette.settingsWindow
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.settingsWindow, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.settingsWindow, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .foregroundStyle(Tokens.Palette.settingsText)
        .tint(Tokens.Palette.accent)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: Tokens.Size.settingsTopInset - 14)
            ForEach(SettingsTab.allCases) { item in
                Button { withAnimation(.snappy(duration: 0.2)) { tab = item } } label: {
                    Label(item.title, systemImage: item.symbol)
                        .labelStyle(SidebarLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 36)
                        .padding(.horizontal, 12)
                        .background(tab == item ? Tokens.Palette.settingsSelected : .clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == item ? .white : Color(hex: 0xE6E6EA))
                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("Signed in via gh").font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                HStack(spacing: 8) {
                    Avatar(login: state.viewerLogin ?? "?", size: 24)
                    Text(state.viewerLogin ?? "Not signed in").font(Tokens.Typo.settingsBody.weight(.semibold))
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 4)
        }
        .padding(.horizontal, 10).padding(.vertical, 14)
        .frame(width: Tokens.Size.settingsSidebarWidth)
        .background(Tokens.Palette.settingsSidebar, in: RoundedRectangle(cornerRadius: Tokens.Radius.settingsSidebar, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.settingsSidebar, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general: GeneralSettingsView(state: state, intents: intents)
        case .notifications: NotificationSettingsView(state: state, intents: intents)
        case .actions: ActionsSettingsView(state: state, intents: intents)
        case .about: AboutSettingsView(state: state)
        }
    }
}

struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.font(.system(size: 13, weight: .semibold)).frame(width: 16)
            configuration.title.font(Tokens.Typo.settingsNav)
        }
    }
}

// MARK: - Shared settings chrome

struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Tokens.Typo.settingsTitle).tracking(-0.26)
            Text(subtitle).font(Tokens.Typo.settingsBody).foregroundStyle(Tokens.Palette.settingsSecondary)
        }
    }
}

struct SettingsCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Palette.settingsCard, in: RoundedRectangle(cornerRadius: Tokens.Radius.settingsCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.settingsCard, style: .continuous)
                    .strokeBorder(Tokens.Palette.settingsCardEdge, lineWidth: 0.5)
            }
    }
}

struct SettingsLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Tokens.Typo.settingsLabel).foregroundStyle(Tokens.Palette.settingsLabel)
    }
}

/// A setting row: label on the left, control on the right, optional note below.
struct SettingsRow<Control: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text(title).font(Tokens.Typo.settingsBody.weight(.semibold))
                Spacer(minLength: 16)
                control
            }
            if let note {
                Text(note).font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct SettingsFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(Tokens.Typo.settingsBody)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Tokens.Palette.settingsField, in: RoundedRectangle(cornerRadius: Tokens.Radius.settingsField, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.settingsField, style: .continuous)
                    .strokeBorder(Tokens.Palette.settingsFieldEdge, lineWidth: 0.5)
            }
    }
}

struct SettingsButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typo.settingsBody.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(fill(configuration.isPressed), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private func fill(_ pressed: Bool) -> Color {
        if prominent { return pressed || hovered ? Color(hex: 0x0858BB) : Tokens.Palette.accent }
        return .white.opacity(pressed ? 0.22 : hovered ? 0.18 : 0.14)
    }
}

/// Wraps children onto new lines, for token chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, origin) in zip(subviews, place(in: bounds.width, subviews: subviews).origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func place(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

struct ValidationNote: View {
    let text: String?

    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(Tokens.Typo.rowSubtitle.weight(.semibold))
                .foregroundStyle(Tokens.Tier.text(.amber))
                .transition(.opacity)
        }
    }
}

struct Avatar: View {
    let login: String
    var size: CGFloat = 30

    var body: some View {
        Text(String(login.prefix(1)).uppercased())
            .font(.system(size: size * 0.44, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }

    private var color: Color {
        let palette: [UInt32] = [0xE0662F, 0x2F9E6E, 0x5856D6, 0x0A66D8, 0xC2498F, 0x8E6B2C]
        let index = login.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count
        return Color(hex: palette[index])
    }
}

extension NudgeIntents {
    /// A binding that writes through `updateSettings`.
    @MainActor
    func setting<Value>(_ keyPath: WritableKeyPath<NudgeSettings, Value>, from state: NudgeState) -> Binding<Value> {
        Binding(get: { state.settings[keyPath: keyPath] },
                set: { value in updateSettings { $0[keyPath: keyPath] = value } })
    }
}
