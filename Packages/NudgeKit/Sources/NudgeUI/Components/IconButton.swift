import SwiftUI

// 28pt icon buttons for row actions and panel headers. While the pointer is over one, the row shows the button's
// name in place of its subtitle (`ActionLabel`), so nothing ever floats over a control; system tooltips don't show
// for inactive apps anyway.
//
// Every control here is `.focusable(false)`: the pill panel never takes keyboard focus, and with Full Keyboard
// Access on, SwiftUI's key-view-loop rebuild for a list of focusable buttons in that panel never returned
// (100% CPU as soon as the pill expanded). The dropdown navigates rows with arrow keys on its focused root instead.

enum IconRole { case normal, accent, secondary }

enum SplitSide { case whole, leading, trailing }

/// The name of the action button under the pointer, shown by the row in place of its subtitle.
@MainActor @Observable
final class ActionLabel {
    var text: String?
    nonisolated init() {}
}

extension EnvironmentValues {
    @Entry var actionLabel: ActionLabel? = nil
}

struct IconButtonStyle: ButtonStyle {
    static let height: CGFloat = 28
    static let mainWidth: CGFloat = 30
    static let chevronWidth: CGFloat = 20

    var role: IconRole = .normal
    var side: SplitSide = .whole
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: side == .trailing ? 9 : 12.5, weight: side == .trailing ? .heavy : .semibold))
            .foregroundStyle(glyph)
            .frame(width: width, height: Self.height)
            .background(fill(configuration.isPressed), in: shape)
            .contentShape(shape)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private var width: CGFloat {
        switch side {
        case .whole: Self.height
        case .leading: Self.mainWidth
        case .trailing: Self.chevronWidth
        }
    }

    private var shape: UnevenRoundedRectangle {
        let r = Self.height / 2
        let leading = side != .trailing, trailing = side != .leading
        return UnevenRoundedRectangle(topLeadingRadius: leading ? r : 0, bottomLeadingRadius: leading ? r : 0,
                                      bottomTrailingRadius: trailing ? r : 0, topTrailingRadius: trailing ? r : 0)
    }

    private var glyph: Color {
        switch role {
        case .accent: .white
        case .normal: Tokens.Palette.text
        case .secondary: Tokens.Palette.secondary
        }
    }

    /// Only Start is filled blue; its chevron segment is a lighter blue so it reads as the same button. Neutral
    /// fills use the row's foreground at ~11% so they still read on a tinted amber or red row.
    private func fill(_ pressed: Bool) -> Color {
        let active = pressed || hovered
        switch role {
        case .accent:
            let base = active ? Color(hex: 0x0858BB) : Tokens.Palette.accent
            return side == .trailing ? base.opacity(0.8) : base
        case .normal, .secondary:
            return Tokens.Palette.text.opacity(pressed ? 0.22 : hovered ? 0.17 : 0.11)
        }
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var role: IconRole = .normal
    var side: SplitSide = .whole
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(IconButtonStyle(role: role, side: side))
            .focusable(false)
            .actionLabel(label)
            .accessibilityLabel(label)
    }
}

/// Icon button whose attached ⌄ segment opens a menu. One pill: main part, hairline, chevron part.
struct SplitIconMenuButton<MenuContent: View>: View {
    let symbol: String
    let label: String
    let menuLabel: String
    var role: IconRole = .normal
    let action: () -> Void
    @ViewBuilder let menu: MenuContent

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: symbol, label: label, role: role, side: .leading, action: action)
            SplitDivider(role: role)
            Menu { menu } label: { Image(systemName: "chevron.down") }
                .menuStyle(.button)
                .buttonStyle(IconButtonStyle(role: role, side: .trailing))
                .menuIndicator(.hidden)
                .focusable(false)
                .fixedSize()
                .actionLabel(menuLabel)
                .accessibilityLabel(menuLabel)
        }
    }
}

/// Icon button whose attached ⌄ segment presents a popover.
struct SplitIconPopoverButton<Popover: View>: View {
    let symbol: String
    let label: String
    let menuLabel: String
    var role: IconRole = .normal
    @Binding var isPresented: Bool
    let action: () -> Void
    @ViewBuilder let popover: Popover

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: symbol, label: label, role: role, side: .leading, action: action)
            SplitDivider(role: role)
            Button { isPresented.toggle() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(IconButtonStyle(role: role, side: .trailing))
                .focusable(false)
                .actionLabel(menuLabel)
                .accessibilityLabel(menuLabel)
                .popover(isPresented: $isPresented, arrowEdge: .bottom) { popover }
        }
    }
}

/// 1pt hairline between the halves of a split button.
private struct SplitDivider: View {
    let role: IconRole

    var body: some View {
        Rectangle()
            .fill(role == .accent ? Color.white.opacity(0.35) : Tokens.Palette.text.opacity(0.14))
            .frame(width: 1, height: IconButtonStyle.height)
    }
}

extension View {
    /// Reports `text` to the enclosing row's `ActionLabel` while hovered.
    func actionLabel(_ text: String) -> some View { modifier(ActionLabelModifier(text: text)) }
}

private struct ActionLabelModifier: ViewModifier {
    let text: String
    @Environment(\.actionLabel) private var label

    func body(content: Content) -> some View {
        content.onHover { inside in
            guard let label else { return }
            if inside { label.text = text } else if label.text == text { label.text = nil }
        }
    }
}
