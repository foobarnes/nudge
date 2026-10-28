import AppKit
import NudgeCore
import SwiftUI

/// Right-click menu for a row in the pill list, the dropdown, or the Snoozed group.
struct RowContextMenu: View {
    let row: PRRow
    let state: NudgeState
    let intents: NudgeIntents
    var isSnoozed = false
    let customSnooze: () -> Void
    let showDetails: () -> Void

    var body: some View {
        Button { intents.open(row) } label: { Label("Open on GitHub", systemImage: "arrow.up.right") }
            .keyboardShortcut("o", modifiers: .command)
        Button { intents.startReview(row, nil) } label: { Label("Start Review", systemImage: "play.fill") }
        Menu {
            ForEach(state.settings.actions) { action in
                Button { intents.startReview(row, action.id) } label: { Label(action.name, systemImage: action.symbol) }
            }
            if state.settings.actions.isEmpty { Text("No actions yet") }
        } label: {
            Label("Run Action", systemImage: "terminal")
        }
        Divider()
        Menu {
            snoozeItem("15 Minutes", .minutes(15))
            snoozeItem("1 Hour", .minutes(60))
            snoozeItem("3 Hours", .minutes(180))
            snoozeItem("Until Tomorrow", .untilTomorrow)
            snoozeItem("Until Next Work Day", .untilNextWorkDay)
            Divider()
            Button("Custom…", action: customSnooze)
        } label: {
            Label("Snooze", systemImage: "moon.zzz")
        }
        if isSnoozed {
            Button { intents.unsnooze(row) } label: { Label("Unsnooze", systemImage: "moon.slash") }
        }
        Button { intents.hide(row) } label: { Label("Hide Until Re-requested", systemImage: "eye.slash") }
        Divider()
        Button { copy(row.pr.url.absoluteString) } label: { Label("Copy Link", systemImage: "link") }
        Button { copy(row.pr.title) } label: { Label("Copy Title", systemImage: "doc.on.doc") }
        Button { copy("\(row.pr.repo)#\(row.pr.number)") } label: {
            Label("Copy “\(row.pr.repo)#\(String(row.pr.number))”", systemImage: "number")
        }
        Button(action: showDetails) { Label("Show Details", systemImage: "info.circle") }
    }

    private func snoozeItem(_ title: String, _ option: SnoozeOption) -> some View {
        let end = SnoozeParser.resolve(option, now: .now, config: state.settings.workHours)
        return Button { intents.snooze(row, option) } label: {
            Text(end.map { "\(title)  (\(Format.weekdayTimeIfNotToday($0)))" } ?? title)
        }
        .disabled(end == nil)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Right-click menu for the collapsed capsule, the expanded pill's chrome, and the dropdown header.
struct PillContextMenu: View {
    let state: NudgeState
    let intents: NudgeIntents
    var includesOpenDropdown = true

    var body: some View {
        if includesOpenDropdown {
            Button { intents.openDropdown() } label: { Label("Open Menu Bar List", systemImage: "menubar.arrow.down.rectangle") }
        }
        Button { intents.syncNow() } label: { Label("Sync Now", systemImage: "arrow.clockwise") }
        Divider()
        Button { intents.dismissPill() } label: { Label("Hide Pill Until Next Request", systemImage: "eye.slash") }
        Menu {
            ForEach([DisplayMode.menuBarOnly, .widgetAlways, .auto], id: \.self) { mode in
                Toggle(isOn: Binding(get: { state.settings.displayMode == mode },
                                     set: { _ in intents.updateSettings { $0.displayMode = mode } })) {
                    Text(mode == .menuBarOnly ? "Menu Bar Only" : mode.title)
                }
            }
        } label: {
            Label("Show Timers", systemImage: "timer")
        }
        Divider()
        Button { intents.openSettings() } label: { Label("Settings…", systemImage: "gearshape") }
            .keyboardShortcut(",", modifiers: .command)
        Button { intents.quit() } label: { Label("Quit Nudge", systemImage: "power") }
            .keyboardShortcut("q", modifiers: .command)
    }
}
