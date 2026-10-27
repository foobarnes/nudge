// TEMPORARY — delete at merge. Stand-ins for NudgeUI views and a DEBUG row seed so the shell can be run before
// NudgeUI and NudgeCore land. App-module types shadow the imported ones with the same names.
import NudgeCore
import SwiftUI

struct PillView: View {
    let state: NudgeState
    let intents: NudgeIntents

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(state.rows.isEmpty ? .green : .orange).frame(width: 9, height: 9)
                Text(state.rows.isEmpty ? "✓" : "\(state.rows.count)").font(.system(size: 17, weight: .heavy, design: .rounded))
                if let oldest = state.oldest {
                    Text("·").foregroundStyle(.secondary)
                    Text(DevSample.age(oldest)).font(.system(size: 19, weight: .heavy, design: .rounded)).monospacedDigit()
                }
            }
            if state.pillExpanded && !state.rows.isEmpty {
                Divider()
                ForEach(state.rows) { row in
                    HStack {
                        DevHoverCard(row: row, demo: row.id == state.rows.first?.id) {
                            Text("\(row.pr.name)#\(String(row.pr.number))").bold()
                        }
                        Text(row.pr.title).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                        Spacer()
                        Menu("Start") {
                            ForEach(state.settings.actions) { a in Button(a.name) { intents.startReview(row, a.id) } }
                        }.fixedSize()
                        Menu("Snooze") { Button("1 hour") { intents.snooze(row, .minutes(60)) } }.fixedSize()
                    }
                }
                HStack {
                    Text("edge \(state.pillEdge.rawValue)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Settings…") { intents.openSettings() }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: state.pillExpanded && !state.rows.isEmpty ? 360 : nil)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .opacity(state.pillDimmed ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.4), value: state.pillDimmed)
    }
}

struct DropdownView: View {
    let state: NudgeState
    let intents: NudgeIntents

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(state.rows) { row in
                Button { intents.open(row) } label: {
                    HStack {
                        DevHoverCard(row: row, demo: row.id == state.rows.first?.id) {
                            Text("\(row.pr.repo)#\(String(row.pr.number))").bold()
                        }
                        Text(row.pr.title).lineLimit(1)
                        Spacer()
                        Text(DevSample.age(row)).monospacedDigit()
                    }
                }.buttonStyle(.plain)
            }
            if state.rows.isEmpty { Text("All clear").foregroundStyle(.secondary) }
            Divider()
            Picker("", selection: Binding(get: { state.settings.displayMode },
                                          set: { m in intents.updateSettings { $0.displayMode = m } })) {
                Text("Menu bar").tag(DisplayMode.menuBarOnly)
                Text("Widget").tag(DisplayMode.widgetAlways)
                Text("Auto").tag(DisplayMode.auto)
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Button("Sync now") { intents.syncNow() }
                Spacer()
                Button("Settings…") { intents.openSettings() }
                Button("Quit") { intents.quit() }
            }
        }
        .padding(14)
        .frame(width: 380)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

struct SettingsRootView: View {
    let state: NudgeState
    let intents: NudgeIntents

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["General", "Notifications", "Actions", "About"], id: \.self) { Text($0) }
                Spacer()
            }
            .padding(.top, 44).padding(16)
            .frame(width: 200)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(10)
            Form {
                Toggle("Launch at login", isOn: Binding(get: { state.settings.launchAtLogin },
                                                        set: { v in intents.updateSettings { $0.launchAtLogin = v } }))
                Text("Placeholder settings").foregroundStyle(.secondary)
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
        }
        .frame(width: 720, height: 480)
        .background(Color(red: 24 / 255, green: 24 / 255, blue: 30 / 255).opacity(0.62))
        .glassEffect(.clear, in: .rect(cornerRadius: 30))
    }
}

/// Stand-in for the UI's row hover card: a SwiftUI popover shown while the label is hovered. With
/// `NUDGE_DEMO_POPOVER=1` the first row's card opens on its own (for automated checks without a pointer).
struct DevHoverCard<Label: View>: View {
    let row: PRRow
    let demo: Bool
    @ViewBuilder let label: Label
    @State private var hovering = false
    @State private var demoShown = false

    var body: some View {
        label
            .onHover { hovering = $0 }
            .popover(isPresented: Binding(get: { hovering || demoShown },
                                          set: { if !$0 { hovering = false; demoShown = false } }),
                     arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.pr.title).bold()
                    Text("via \(row.pr.via.label)").foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .task {
                guard demo, ProcessInfo.processInfo.environment["NUDGE_DEMO_POPOVER"] == "1" else { return }
                try? await Task.sleep(for: .seconds(0.1))
                demoShown = true
            }
    }
}

/// Seeds synthetic rows when a fixture is passed (the stub engine ignores fixtures). A file name containing
/// "zero" seeds none.
enum NudgeEngineFactory {
    @MainActor static func make(state: NudgeState, fixtureURL: URL? = nil) -> NudgeEngine {
        let engine = NudgeCore.NudgeEngineFactory.make(state: state, fixtureURL: fixtureURL)
        #if DEBUG
        if let fixtureURL, !fixtureURL.lastPathComponent.contains("zero") { state.rows = DevSample.rows() }
        if ProcessInfo.processInfo.environment["NUDGE_DEMO_POPOVER"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                state.pillExpanded = true
            }
        }
        #endif
        return engine
    }
}

enum DevSample {
    static func rows(now: Date = .now) -> [PRRow] {
        let specs: [(String, Int, String, Double, Tier, RequestTarget)] = [
            ("acme/api", 4211, "Fix token refresh", 4.2, .amber, .direct),
            ("acme/web", 930, "Export to CSV", 1.06, .fresh, .direct),
            ("acme/infra", 88, "Bump deps", 0.35, .fresh, .team(org: "acme", slug: "backend")),
        ]
        return specs.map { repo, number, title, hours, tier, via in
            let since = now.addingTimeInterval(-hours * 3600)
            let pr = WaitingPR(prID: "PR_\(number)", repo: repo, number: number, title: title,
                               url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: "octocat",
                               headRef: "feature-\(number)", via: via, requestedBy: "octocat",
                               requestKey: "RRE_\(number)", requestedAt: since, waitingSince: since)
            return PRRow(pr: pr, level: .notify, tier: tier, workSeconds: hours * 3600, workSecondsToNextTier: nil,
                         snoozedUntil: nil, computedAt: now)
        }
    }

    static func age(_ row: PRRow) -> String {
        let s = Int(Date().timeIntervalSince(row.pr.waitingSince ?? .now))
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
}
