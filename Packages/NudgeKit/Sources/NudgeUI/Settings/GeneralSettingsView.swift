import AppKit
import NudgeCore
import SwiftUI

struct GeneralSettingsView: View {
    let state: NudgeState
    let intents: NudgeIntents
    @State private var amberText = ""
    @State private var redText = ""

    private var settings: NudgeSettings { state.settings }

    /// Supported terminals that are installed, plus the current choice so the picker never shows a blank.
    private var installedTerminals: [TerminalApp] {
        TerminalApp.allCases.filter {
            $0 == settings.terminalApp || NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeader(title: "General", subtitle: "Where timers show, when the work clock runs, and how urgency escalates.")

                SettingsCard {
                    SettingsRow(title: "Show timers", note: settings.displayMode.hint) {
                        Segmented(segments: [
                            .init(option: DisplayMode.menuBarOnly, title: "Menu bar"),
                            .init(option: .widgetAlways, title: "Widget"),
                            .init(option: .auto, title: "Auto"),
                        ], selection: intents.setting(\.displayMode, from: state),
                        trackFill: .black.opacity(0.28), selectedFill: .white.opacity(0.18),
                        text: Tokens.Palette.settingsLabel, selectedText: .white, height: 28)
                        .frame(width: 270)
                    }
                    Divider().overlay(.white.opacity(0.07))
                    SettingsRow(title: "Launch at login") {
                        Toggle("Launch at login", isOn: intents.setting(\.launchAtLogin, from: state))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsLabel("Working hours")
                        WeekdayPicker(selection: intents.setting(\.workHours.weekdays, from: state))
                        HStack(spacing: 12) {
                            MinutePicker(title: "Start", minute: intents.setting(\.workHours.startMinute, from: state))
                            Text("to").foregroundStyle(Tokens.Palette.settingsSecondary)
                            MinutePicker(title: "End", minute: intents.setting(\.workHours.endMinute, from: state))
                            Spacer()
                        }
                        ValidationNote(text: hoursProblem)
                        Text("Work time only counts inside these hours. Tier colors and reminders pause outside them.")
                            .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsLabel("Escalation")
                        HStack(spacing: 18) {
                            thresholdField("Amber after", text: $amberText, tier: .amber, commit: commitAmber)
                            thresholdField("Red after", text: $redText, tier: .red, commit: commitRed)
                            Spacer()
                        }
                        ValidationNote(text: thresholdProblem)
                        Text("Working hours of waiting before a request turns amber, then red. Red sends one reminder.")
                            .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                    }
                }

                SettingsCard {
                    SettingsRow(title: "Default snooze", note: "What one click on Snooze does. The ⌄ menu always offers every option.") {
                        Picker("Default snooze", selection: intents.setting(\.defaultSnooze, from: state)) {
                            Text("15 minutes").tag(SnoozeOption.minutes(15))
                            Text("1 hour").tag(SnoozeOption.minutes(60))
                            Text("3 hours").tag(SnoozeOption.minutes(180))
                            Text("Until tomorrow").tag(SnoozeOption.untilTomorrow)
                            Text("Until next work day").tag(SnoozeOption.untilNextWorkDay)
                        }
                        .labelsHidden().frame(width: 190)
                    }
                    Divider().overlay(.white.opacity(0.07))
                    SettingsRow(title: "Terminal app", note: "Terminal actions open here. Lists the supported terminals you have installed. Terminal.app needs Automation permission.") {
                        Picker("Terminal app", selection: intents.setting(\.terminalApp, from: state)) {
                            ForEach(installedTerminals, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().frame(width: 190)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear { syncThresholdText() }
        .onChange(of: settings.thresholds) { syncThresholdText() }
    }

    private var hoursProblem: String? {
        if settings.workHours.weekdays.isEmpty { return "With no working days, tiers never escalate and “next work day” snoozes are off." }
        if settings.workHours.startMinute >= settings.workHours.endMinute { return "Start must be before end. Overnight ranges aren't supported yet." }
        return nil
    }

    private var thresholdProblem: String? {
        guard let amber = Double(amberText), let red = Double(redText) else { return "Enter hours as numbers, like 4 or 7.5." }
        if amber <= 0 { return "Amber must be more than 0 hours." }
        if red <= amber { return "Red must come after amber." }
        return nil
    }

    private func thresholdField(_ title: String, text: Binding<String>, tier: Tier, commit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TierDot(tier: tier, isTeam: false, size: 9)
            Text(title).font(Tokens.Typo.settingsBody.weight(.semibold))
            TextField("hours", text: text)
                .textFieldStyle(SettingsFieldStyle())
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { commit() }
            Text("working hours").font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
        }
    }

    private func syncThresholdText() {
        amberText = Self.hours(settings.thresholds.amberWorkHours)
        redText = Self.hours(settings.thresholds.redWorkHours)
    }

    private func commitAmber() {
        guard thresholdProblem == nil, let amber = Double(amberText) else { return }
        intents.updateSettings { $0.thresholds.amberWorkHours = amber }
    }

    private func commitRed() {
        guard thresholdProblem == nil, let red = Double(redText) else { return }
        intents.updateSettings { $0.thresholds.redWorkHours = red }
    }

    private static func hours(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(Tokens.Typo.settingsBody.weight(.bold))
                        .foregroundStyle(on ? .white : Tokens.Palette.settingsSecondary)
                        .frame(width: 32, height: 32)
                        .background(on ? Tokens.Palette.accent : .black.opacity(0.28), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}

/// Hour/minute picker backed by minutes-after-midnight.
struct MinutePicker: View {
    let title: String
    @Binding var minute: Int

    private var date: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }

    var body: some View {
        DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 92)
            .accessibilityLabel(title)
    }
}
