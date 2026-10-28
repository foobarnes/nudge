import NudgeCore
import SwiftUI

struct NotificationSettingsView: View {
    let state: NudgeState
    let intents: NudgeIntents
    @State private var newRepo = ""
    @State private var addProblem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeader(title: "Notifications", subtitle: "Pick how each organization reaches you. A repo can override its org.")
                legend
                ForEach(orgs) { org in
                    SettingsCard(padding: 6) {
                        OrgRulesCard(org: org, overrides: overrides(for: org.login), state: state, intents: intents)
                    }
                }
                HStack(spacing: 10) {
                    TextField("owner/repo", text: $newRepo)
                        .textFieldStyle(SettingsFieldStyle())
                        .frame(width: 260)
                        .onSubmit(addOverride)
                        .accessibilityLabel("Add repo override")
                    Button("Add repo override", action: addOverride).buttonStyle(SettingsButtonStyle())
                    ValidationNote(text: addProblem)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var orgs: [OrgSummary] {
        var seen = Set(state.knownOrgs.map(\.login))
        var all = state.knownOrgs
        for repo in state.settings.repoRules.keys {
            let owner = String(repo.split(separator: "/").first ?? "")
            if !owner.isEmpty, seen.insert(owner).inserted {
                all.append(OrgSummary(login: owner, isViewer: owner == state.viewerLogin, waitingCount: 0))
            }
        }
        return all.sorted { ($0.isViewer ? 1 : 0, $0.login) < ($1.isViewer ? 1 : 0, $1.login) }
    }

    private func overrides(for org: String) -> [String] {
        state.settings.repoRules.keys.filter { $0.hasPrefix(org + "/") }.sorted()
    }

    private var legend: some View {
        SettingsCard(padding: 0) {
            HStack(spacing: 18) {
                legendItem("Notify: banner and timer") { Circle().fill(Tokens.Palette.accent) }
                legendItem("Silent: timer only") { Circle().fill(.white.opacity(0.5)) }
                legendItem("Hidden: ignored") { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1) }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func legendItem<Swatch: View>(_ text: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 7) {
            swatch().frame(width: 8, height: 8)
            Text(text).font(Tokens.Typo.rowSubtitle).foregroundStyle(Color(hex: 0xD6D6DB))
        }
    }

    private func addOverride() {
        let repo = newRepo.trimmingCharacters(in: .whitespaces).lowercased()
        guard let problem = Self.validate(repo) else {
            intents.updateSettings { $0.repoRules[repo] = .silent }
            newRepo = ""
            addProblem = nil
            return
        }
        addProblem = problem
    }

    static func validate(_ repo: String) -> String? {
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return "Use the form owner/repo." }
        let owner = parts[0], name = parts[1]
        let ownerOK = !owner.isEmpty && owner.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        let nameOK = !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        return ownerOK && nameOK ? nil : "Owner and repo may use letters, numbers, - _ and . only."
    }
}

struct OrgRulesCard: View {
    let org: OrgSummary
    let overrides: [String]
    let state: NudgeState
    let intents: NudgeIntents

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Avatar(login: org.login)
                VStack(alignment: .leading, spacing: 1) {
                    Text(org.login).font(Tokens.Typo.settingsBody.weight(.bold))
                    Text(subtitle).font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                }
                Spacer()
                NotifyLevelPicker(level: orgLevel).accessibilityLabel(org.login)
            }
            .padding(10)
            if !overrides.isEmpty {
                VStack(spacing: 0) {
                    ForEach(overrides, id: \.self) { repo in
                        HStack(spacing: 12) {
                            Image(systemName: "doc").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Tokens.Palette.settingsSecondary)
                            Text(repo).font(Tokens.Typo.settingsBody.weight(.semibold))
                            Spacer()
                            NotifyLevelPicker(level: repoLevel(repo)).accessibilityLabel(repo)
                            Button { intents.updateSettings { $0.repoRules[repo] = nil } } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Tokens.Palette.settingsSecondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove override for \(repo)")
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10)
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.14)).frame(width: 1.5) }
                .padding(.leading, 31)
            }
        }
    }

    private var subtitle: String {
        if org.isViewer { return "Your personal repos" }
        return org.waitingCount == 1 ? "1 waiting" : "\(org.waitingCount) waiting"
    }

    private var orgLevel: Binding<NotifyLevel> {
        Binding(get: { state.settings.orgRules[org.login] ?? .notify },
                set: { level in intents.updateSettings { $0.orgRules[org.login] = level } })
    }

    private func repoLevel(_ repo: String) -> Binding<NotifyLevel> {
        Binding(get: { state.settings.repoRules[repo] ?? .notify },
                set: { level in intents.updateSettings { $0.repoRules[repo] = level } })
    }
}

struct NotifyLevelPicker: View {
    @Binding var level: NotifyLevel

    var body: some View {
        Segmented(segments: [
            .init(option: NotifyLevel.notify, title: "Notify", selectedFill: Tokens.Palette.accent),
            .init(option: .silent, title: "Silent", selectedFill: .white.opacity(0.18)),
            .init(option: .hidden, title: "Hidden", selectedFill: .white.opacity(0.1)),
        ], selection: $level, trackFill: .black.opacity(0.28), text: Tokens.Palette.settingsLabel, selectedText: .white, height: 28)
        .frame(width: 270)
    }
}
