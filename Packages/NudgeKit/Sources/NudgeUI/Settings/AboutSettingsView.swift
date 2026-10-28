import NudgeCore
import SwiftUI

struct AboutSettingsView: View {
    let state: NudgeState
    let intents: NudgeIntents

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "About", subtitle: "A small nudge for the reviews waiting on you.")
            SettingsCard {
                HStack(spacing: 14) {
                    Image(systemName: "clock.badge")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Tokens.Palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nudge").font(Tokens.Typo.heading)
                        Text("Version \(version)").font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                        if let updates = state.updates { UpdateLine(status: updates) }
                    }
                    Spacer()
                    if let updates = state.updates { updateButton(updates.phase) }
                    Link(destination: URL(string: "https://github.com/foobarnes/nudge")!) {
                        Label("Source on GitHub", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(SettingsButtonStyle())
                }
                if let updates = state.updates {
                    Divider().overlay(.white.opacity(0.07)).padding(.top, 14).padding(.bottom, 6)
                    SettingsRow(title: "Check for updates automatically",
                                note: "Nudge checks hourly, then installs and relaunches in about a second.") {
                        Toggle("Check for updates automatically", isOn: Binding(
                            get: { updates.checksAutomatically }, set: { intents.setChecksForUpdatesAutomatically($0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel("GitHub access")
                    HStack(spacing: 10) {
                        Image(systemName: state.viewerLogin == nil ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle.badge.checkmark")
                            .foregroundStyle(state.viewerLogin == nil ? Tokens.Tier.text(.amber) : Tokens.Palette.ok)
                        Text(state.viewerLogin.map { "Signed in as \($0) via gh" } ?? "Not signed in. Run gh auth login.")
                            .font(Tokens.Typo.settingsBody.weight(.semibold))
                    }
                    Text("Nudge reads review requests through the gh CLI on your PATH and never stores a token of its own.")
                        .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                }
            }
        }
    }

    @ViewBuilder private func updateButton(_ phase: UpdateStatus.Phase) -> some View {
        switch phase {
        case .available:
            Button("Update", action: intents.installUpdate).buttonStyle(SettingsButtonStyle(prominent: true))
        case .failed:
            Button("Try Again", action: intents.checkForUpdates).buttonStyle(SettingsButtonStyle())
        default:
            Button("Check for Updates", action: intents.checkForUpdates)
                .buttonStyle(SettingsButtonStyle())
                .disabled(phase == .checking)
                .opacity(phase == .checking ? 0.5 : 1)
        }
    }
}

/// One line under the version: what the last update check found.
private struct UpdateLine: View {
    let status: UpdateStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status.phase {
            case .idle:
                if let date = status.lastChecked { Text("Last checked \(Format.ago(date))") }
            case .checking:
                ProgressView().controlSize(.mini)
                Text("Checking for updates…")
            case .upToDate:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.Palette.ok)
                Text("You're on the latest version")
            case let .available(version):
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Tokens.Palette.tokenText)
                Text("Version \(version) is available").foregroundStyle(Tokens.Palette.settingsText)
            case let .failed(message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.Tier.text(.amber))
                Text(message).lineLimit(1).truncationMode(.tail)
            }
        }
        .font(Tokens.Typo.rowSubtitle)
        .foregroundStyle(Tokens.Palette.settingsSecondary)
    }
}
