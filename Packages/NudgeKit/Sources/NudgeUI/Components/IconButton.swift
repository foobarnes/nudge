import SwiftUI

// 26pt circular icon buttons for row actions and panel headers, with a custom mini label after 600ms hover
// (system tooltips don't show for inactive apps).

enum IconRole { case normal, accent, secondary }

enum SplitSide { case whole, leading, trailing }

struct IconButtonStyle: ButtonStyle {
    var role: IconRole = .normal
    var side: SplitSide = .whole
    var width: CGFloat = 26
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: width, height: 26)
            .background(fill(configuration.isPressed), in: shape)
            .overlay { shape.strokeBorder(.white.opacity(role == .accent ? 0.18 : 0.25), lineWidth: 0.5) }
            .padding(1)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private var shape: UnevenRoundedRectangle {
        let r: CGFloat = 13
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

    private func fill(_ pressed: Bool) -> Color {
        switch role {
        case .accent: pressed || hovered ? Color(hex: 0x0858BB) : Tokens.Palette.accent
        case .normal, .secondary: pressed || hovered ? Tokens.Palette.fillStrong : Tokens.Palette.fillHover
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
            .miniLabel(label)
            .accessibilityLabel(label)
    }
}

/// Icon button whose attached ⌄ segment opens a menu.
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
            Menu { menu } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy)) }
                .menuStyle(.button)
                .buttonStyle(IconButtonStyle(role: role, side: .trailing, width: 14))
                .menuIndicator(.hidden)
                .fixedSize()
                .miniLabel(menuLabel)
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
            Button { isPresented.toggle() } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy)) }
                .buttonStyle(IconButtonStyle(role: role, side: .trailing, width: 14))
                .miniLabel(menuLabel)
                .accessibilityLabel(menuLabel)
                .popover(isPresented: $isPresented, arrowEdge: .bottom) { popover }
        }
    }
}

extension View {
    func miniLabel(_ text: String) -> some View { modifier(MiniLabelModifier(text: text)) }
}

extension EnvironmentValues {
    /// Forces every mini label visible (previews and the gallery).
    @Entry public var miniLabelsVisible = false
}

private struct MiniLabelModifier: ViewModifier {
    let text: String
    @Environment(\.miniLabelsVisible) private var forced
    @State private var hovered = false
    @State private var task: Task<Void, Never>?

    private var shown: Bool { hovered || forced }

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                task?.cancel()
                if inside {
                    task = Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        if !Task.isCancelled { hovered = true }
                    }
                } else {
                    hovered = false
                }
            }
            .overlay(alignment: .bottom) {
                if shown {
                    Text(text)
                        .font(Tokens.Typo.caption)
                        .foregroundStyle(Tokens.Palette.text)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().strokeBorder(Tokens.Palette.hairline, lineWidth: 0.5) }
                        .fixedSize()
                        .alignmentGuide(.bottom) { $0[.top] - 4 }
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: shown)
            .zIndex(shown ? 1 : 0)
    }
}
