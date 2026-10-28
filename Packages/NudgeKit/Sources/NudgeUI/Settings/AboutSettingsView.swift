import AppKit
import NudgeCore
import SwiftUI

struct AboutSettingsView: View {
    let state: NudgeState

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
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        // The wordmark: lowercase, rounded black.
                        Text("nudge").font(.system(size: 26, weight: .black, design: .rounded)).accessibilityLabel("Nudge")
                        Text("Version \(version)").font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                    }
                    Spacer()
                    Link(destination: URL(string: "https://github.com/foobarnes/nudge")!) {
                        Label("Source on GitHub", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(SettingsButtonStyle())
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
}
