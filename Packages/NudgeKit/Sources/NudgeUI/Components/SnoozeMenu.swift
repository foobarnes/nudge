import NudgeCore
import SwiftUI

/// Snooze presets with their end times plus a Custom field parsed by `SnoozeParser`.
struct SnoozeMenu: View {
    let row: PRRow
    let state: NudgeState
    let intents: NudgeIntents
    let dismiss: () -> Void
    @State private var custom = ""
    @State private var invalid = false
    @FocusState private var fieldFocused: Bool

    private struct Preset: Identifiable {
        let option: SnoozeOption
        let title: String
        var id: String { title }
    }

    private static let presets = [
        Preset(option: .minutes(15), title: "15 minutes"), Preset(option: .minutes(60), title: "1 hour"),
        Preset(option: .minutes(180), title: "3 hours"), Preset(option: .untilTomorrow, title: "Until tomorrow"),
        Preset(option: .untilNextWorkDay, title: "Until next work day"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.presets) { preset in
                let option = preset.option
                let end = SnoozeParser.resolve(option, now: .now, config: state.settings.workHours)
                let disabled = end == nil
                Button {
                    choose(option)
                } label: {
                    HStack(spacing: 16) {
                        Text(preset.title)
                        Spacer(minLength: 0)
                        Text(end.map { Format.weekdayTimeIfNotToday($0) } ?? "No work days")
                            .font(Tokens.Typo.menuHint)
                            .foregroundStyle(option == state.settings.defaultSnooze ? .white.opacity(0.85) : Tokens.Palette.secondary)
                    }
                }
                .buttonStyle(MenuItemStyle(selected: option == state.settings.defaultSnooze))
                .disabled(disabled)
                .opacity(disabled ? 0.5 : 1)
            }
            Divider().padding(.vertical, 4).padding(.horizontal, 6)
            HStack(spacing: 8) {
                Text("Custom").font(Tokens.Typo.menuItem).fontWeight(.semibold)
                TextField("45m", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .font(Tokens.Typo.menuItem.weight(.bold))
                    .frame(width: 70)
                    .focused($fieldFocused)
                    .onSubmit(setCustom)
                Text(invalid ? "Try 45m, 4pm, mon" : "or 4pm, mon")
                    .font(Tokens.Typo.menuHint)
                    .foregroundStyle(invalid ? Tokens.Palette.warning : Tokens.Palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                Button("Set", action: setCustom)
                    .buttonStyle(MiniButtonStyle(role: .primary))
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .padding(6)
        .frame(width: 320)
        .onAppear { custom = state.settings.lastCustomSnoozeText ?? "" }
        .accessibilityLabel("Snooze options")
    }

    private func choose(_ option: SnoozeOption) {
        intents.snooze(row, option)
        dismiss()
    }

    private func setCustom() {
        let text = custom.trimmingCharacters(in: .whitespaces)
        guard let end = SnoozeParser.parse(text, now: .now, config: state.settings.workHours) else {
            invalid = true
            fieldFocused = true
            return
        }
        invalid = false
        intents.updateSettings { $0.lastCustomSnoozeText = text }
        choose(.until(end))
    }
}

struct MenuItemStyle: ButtonStyle {
    var selected = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typo.menuItem.weight(.semibold))
            .foregroundStyle(selected ? .white : Tokens.Palette.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill(pressed: configuration.isPressed),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.menuItem, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        if selected { return Tokens.Palette.accent }
        return pressed ? Tokens.Palette.fillStrong : hovered ? Tokens.Palette.fillHover : .clear
    }
}

extension SnoozeOption {
    /// "1 hour", "until tomorrow": completes "Snooze …" in labels.
    var longLabel: String {
        switch self {
        case let .minutes(m):
            if m % 60 == 0 { return m == 60 ? "1 hour" : "\(m / 60) hours" }
            return "\(m) minutes"
        case .untilTomorrow: return "until tomorrow"
        case .untilNextWorkDay: return "until next work day"
        case let .until(date): return "until \(Format.weekdayTimeIfNotToday(date))"
        }
    }
}
