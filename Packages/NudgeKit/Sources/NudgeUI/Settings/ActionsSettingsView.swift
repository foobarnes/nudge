import NudgeCore
import SwiftUI

struct ActionsSettingsView: View {
    let state: NudgeState
    let intents: NudgeIntents
    @State private var selectedID: ReviewAction.ID?

    private var actions: [ReviewAction] { state.settings.actions }
    private var selected: ReviewAction? { actions.first { $0.id == selectedID } ?? actions.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                SettingsHeader(title: "Start review actions",
                               subtitle: "Checked actions all run when you press Start. Any action can also run alone from the Start menu.")
                Spacer()
                Button("New action", action: addAction).buttonStyle(SettingsButtonStyle(prominent: true))
            }
            HStack(alignment: .top, spacing: 14) {
                SettingsCard(padding: 6) { list }
                    .frame(width: 260)
                SettingsCard(padding: 18) {
                    if let selected {
                        ActionEditor(action: binding(for: selected), terminal: state.settings.terminalApp,
                                     allowedSchemes: intents.setting(\.allowedURLSchemes, from: state),
                                     delete: { remove(selected) })
                    } else {
                        Text("Add an action to run when you start a review.")
                            .font(Tokens.Typo.settingsBody).foregroundStyle(Tokens.Palette.settingsSecondary)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                ActionCardRow(action: action, selected: action.id == selected?.id,
                              runOnStart: binding(for: action).runOnStart,
                              canMoveUp: index > 0, canMoveDown: index < actions.count - 1,
                              select: { selectedID = action.id }, move: { move(action, by: $0) })
            }
            if actions.isEmpty {
                Text("No actions yet. Start opens the PR in your browser.")
                    .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                    .padding(12)
            }
        }
        .motion(Motion.rowSlide, value: actions.map(\.id))
    }

    private func binding(for action: ReviewAction) -> Binding<ReviewAction> {
        Binding(get: { state.settings.actions.first { $0.id == action.id } ?? action },
                set: { updated in
                    intents.updateSettings { settings in
                        if let i = settings.actions.firstIndex(where: { $0.id == action.id }) { settings.actions[i] = updated }
                    }
                })
    }

    private func addAction() {
        let action = ReviewAction(name: "New action", symbol: "terminal", kind: .terminal, template: "", runOnStart: true)
        intents.updateSettings { $0.actions.append(action) }
        selectedID = action.id
    }

    private func remove(_ action: ReviewAction) {
        intents.updateSettings { $0.actions.removeAll { $0.id == action.id } }
        selectedID = nil
    }

    private func move(_ action: ReviewAction, by delta: Int) {
        intents.updateSettings { settings in
            guard let i = settings.actions.firstIndex(where: { $0.id == action.id }) else { return }
            let j = i + delta
            guard settings.actions.indices.contains(j) else { return }
            settings.actions.swapAt(i, j)
        }
    }
}

private struct ActionCardRow: View {
    let action: ReviewAction
    let selected: Bool
    @Binding var runOnStart: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let move: (Int) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: action.symbol.isEmpty ? "questionmark" : action.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(action.kind.iconTint)
                .frame(width: 30, height: 30)
                .background(action.kind.iconFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(action.name).font(Tokens.Typo.settingsBody.weight(.bold)).lineLimit(1)
                HStack(spacing: 5) {
                    SettingsChip(action.kind.title)
                    if action.repeatCount > 1 { SettingsChip("×\(action.repeatCount)") }
                }
            }
            Spacer(minLength: 4)
            if hovered {
                VStack(spacing: 0) {
                    reorderButton("chevron.up", enabled: canMoveUp) { move(-1) }
                    reorderButton("chevron.down", enabled: canMoveDown) { move(1) }
                }
                .transition(.opacity)
            }
            Toggle("Run \(action.name) on Start", isOn: $runOnStart)
                .labelsHidden().toggleStyle(.checkbox)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Tokens.Palette.accent.opacity(0.28) : hovered ? .white.opacity(0.05) : .clear)
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x5AA0FF).opacity(0.45), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction(named: "Move up") { move(-1) }
        .accessibilityAction(named: "Move down") { move(1) }
    }

    private func reorderButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 8, weight: .heavy)).frame(width: 18, height: 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tokens.Palette.settingsSecondary)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

struct SettingsChip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Tokens.Typo.caption)
            .foregroundStyle(Color(hex: 0xD6D6DB))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct ActionEditor: View {
    @Binding var action: ReviewAction
    let terminal: TerminalApp
    @Binding var allowedSchemes: [String]
    let delete: () -> Void
    @State private var schemesText = ""

    private static let tokens = ["{url}", "{repo}", "{owner}", "{name}", "{number}", "{branch}", "{title}"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                field("Name") { TextField("Name", text: $action.name).textFieldStyle(SettingsFieldStyle()) }
                field("Runs as") {
                    Segmented(segments: [
                        .init(option: ReviewAction.Kind.terminal, title: "Terminal"),
                        .init(option: .background, title: "Background"),
                        .init(option: .openURL, title: "Open URL"),
                    ], selection: $action.kind, trackFill: .black.opacity(0.28), selectedFill: .white.opacity(0.18),
                    text: Tokens.Palette.settingsLabel, selectedText: .white, height: 28)
                    .fixedSize()
                }
            }
            HStack(alignment: .top, spacing: 12) {
                field("Symbol") { SymbolPicker(symbol: $action.symbol) }
                if action.kind == .openURL {
                    field("Allowed URL schemes") {
                        TextField("https, diagram", text: $schemesText)
                            .textFieldStyle(SettingsFieldStyle())
                            .onSubmit(commitSchemes)
                            .onChange(of: schemesText) { commitSchemes() }
                    }
                } else {
                    Spacer()
                }
            }
            field(action.kind == .openURL ? "URL" : "Command") {
                TemplateEditor(text: $action.template)
                FlowLayout(spacing: 6) {
                    ForEach(Self.tokens, id: \.self) { token in
                        Button(token) { insert(token) }.buttonStyle(TokenChipStyle())
                    }
                    Text("Click to insert").font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                        .padding(.leading, 4)
                }
            }
            HStack(spacing: 22) {
                HStack(spacing: 10) {
                    SettingsLabel("Repeat")
                    RepeatStepper(value: $action.repeatCount)
                }
                Toggle("Run when I press Start", isOn: $action.runOnStart)
                    .toggleStyle(.checkbox)
                    .font(Tokens.Typo.settingsBody.weight(.semibold))
                    .fixedSize()
                Spacer()
                if action.kind == .terminal {
                    HStack(spacing: 6) {
                        Text("Opens in").font(Tokens.Typo.settingsBody).foregroundStyle(Color(hex: 0xD6D6DB))
                        SettingsChip(terminal.title)
                    }
                    .fixedSize()
                }
            }
            Spacer(minLength: 0)
            preview
            HStack {
                Spacer()
                Button("Delete action", role: .destructive, action: delete)
                    .buttonStyle(SettingsButtonStyle())
            }
        }
        .onAppear { schemesText = allowedSchemes.joined(separator: ", ") }
        .onChange(of: action.id) { schemesText = allowedSchemes.joined(separator: ", ") }
    }

    private var problems: [String] {
        ActionRendering.problems(template: action.template, kind: action.kind, allowedSchemes: allowedSchemes)
    }

    @ViewBuilder private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsLabel("Preview with a sample PR")
            Group {
                switch rendered {
                case let .success(.shell(script)):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(script.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                            Text(String(line))
                                .foregroundStyle(line.hasPrefix("export ") || line.hasPrefix("emulate") || line.hasPrefix("trap") ? Color(hex: 0x8E8E93) : Tokens.Palette.settingsText)
                        }
                    }
                case let .success(.url(url)):
                    Text(url.absoluteString).foregroundStyle(Tokens.Palette.settingsText)
                case let .failure(error):
                    Text((error as? ActionTemplateError)?.message ?? error.localizedDescription)
                        .foregroundStyle(Tokens.Tier.text(.amber))
                }
            }
            .font(Tokens.Typo.codeSmall)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            ForEach(problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typo.rowSubtitle.weight(.semibold)).foregroundStyle(Tokens.Tier.text(.amber))
            }
            if problems.isEmpty {
                Label(action.kind == .openURL ? "Tokens are percent-encoded into the URL" : "PR text is passed as data, never as code",
                      systemImage: "checkmark.shield")
                    .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.ok)
            }
        }
    }

    private var rendered: Result<RenderedAction, Error> {
        Result { try ActionRendering.render(action, pr: ActionPreview.pr, allowedSchemes: allowedSchemes) }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsLabel(label)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insert(_ token: String) {
        let needsSpace = !(action.template.isEmpty || action.template.hasSuffix(" ") || action.kind == .openURL)
        action.template += (needsSpace ? " " : "") + token
    }

    private func commitSchemes() {
        allowedSchemes = schemesText.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}

private struct TemplateEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(Tokens.Typo.code)
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minHeight: 44, maxHeight: 88)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tokens.Palette.settingsFieldEdge, lineWidth: 0.5)
            }
            .accessibilityLabel("Template")
    }
}

private struct TokenChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typo.codeSmall)
            .foregroundStyle(Tokens.Palette.tokenText)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Tokens.Palette.tokenChip.opacity(configuration.isPressed ? 1.6 : 1),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct RepeatStepper: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 0) {
            step("minus", enabled: value > 1) { value -= 1 }
            Text("\(value)").font(Tokens.Typo.settingsBody.weight(.bold)).monospacedDigit().frame(width: 22)
                .contentTransition(.numericText()).animation(Motion.roll, value: value)
            step("plus", enabled: value < 20) { value += 1 }
        }
        .padding(2)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Repeat")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(20, value + 1)
            case .decrement: value = max(1, value - 1)
            @unknown default: break
            }
        }
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

extension ReviewAction.Kind {
    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .background: "Background"
        case .openURL: "Open URL"
        }
    }

    var iconFill: Color {
        switch self {
        case .terminal: Color(hex: 0x2B2B33)
        case .background: Color(hex: 0x1F6B4F)
        case .openURL: Color(hex: 0x6B4FD8)
        }
    }

    var iconTint: Color {
        self == .terminal ? Tokens.Palette.ok : .white
    }
}
