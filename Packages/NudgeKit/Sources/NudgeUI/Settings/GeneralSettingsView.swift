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
                            .labelsHidden().toggleStyle(SettingsSwitchStyle())
                    }
                    Divider().overlay(.white.opacity(0.07))
                    SettingsRow(title: "Show Nudge in the Dock", note: "Only while Settings is open. Off keeps Nudge in the menu bar alone.") {
                        Toggle("Show Nudge in the Dock", isOn: intents.setting(\.showInDock, from: state))
                            .labelsHidden().toggleStyle(SettingsSwitchStyle())
                    }
                }

                SettingsCard {
                    SettingsRow(title: "Jiggle on new requests", note: "The widget wiggles when a request arrives, then every 12 working minutes until you open it. A glow instead with Reduce Motion.") {
                        Toggle("Jiggle on new requests", isOn: intents.setting(\.jiggleOnNewRequests, from: state))
                            .labelsHidden().toggleStyle(SettingsSwitchStyle())
                    }
                    Divider().overlay(.white.opacity(0.07))
                    SettingsRow(title: "Play sound on new requests", note: "A soft tink on arrival (unless the banner already chimes) and with each reminder.") {
                        Toggle("Play sound on new requests", isOn: intents.setting(\.soundOnNewRequests, from: state))
                            .labelsHidden().toggleStyle(SettingsSwitchStyle())
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsLabel("Working hours")
                        HStack(spacing: 20) {
                            WeekdayPicker(selection: intents.setting(\.workHours.weekdays, from: state))
                            HStack(spacing: 10) {
                                MinutePicker(title: "Start", minute: intents.setting(\.workHours.startMinute, from: state))
                                Text("to").font(Tokens.Typo.settingsBody).foregroundStyle(Tokens.Palette.settingsSecondary)
                                MinutePicker(title: "End", minute: intents.setting(\.workHours.endMinute, from: state))
                            }
                            Spacer()
                        }
                        ValidationNote(text: hoursProblem)
                        Text("Work time only counts inside these hours. Tier colors and reminders pause outside them.")
                            .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                    }
                    .padding(.vertical, 6)
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsLabel("Escalation")
                        HStack(spacing: 28) {
                            thresholdField("Amber after", text: $amberText, tier: .amber, commit: commitAmber)
                            thresholdField("Red after", text: $redText, tier: .red, commit: commitRed)
                            Spacer()
                        }
                        ValidationNote(text: thresholdProblem)
                        Text("Working hours of waiting before a request turns amber, then red. Red sends one reminder.")
                            .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                    }
                    .padding(.vertical, 6)
                }

                SettingsCard {
                    SettingsRow(title: "Default snooze", note: "What one click on Snooze does. The ⌄ menu always offers every option.") {
                        SettingsMenu(title: "Default snooze", selection: intents.setting(\.defaultSnooze, from: state), options: [
                            (SnoozeOption.minutes(15), "15 minutes"),
                            (.minutes(60), "1 hour"),
                            (.minutes(180), "3 hours"),
                            (.untilTomorrow, "Until tomorrow"),
                            (.untilNextWorkDay, "Until next work day"),
                        ])
                        .frame(width: Self.menuWidth)
                    }
                    Divider().overlay(.white.opacity(0.07))
                    SettingsRow(title: "Terminal app", note: "Terminal actions open here. Lists the supported terminals you have installed. Terminal.app needs Automation permission.") {
                        SettingsMenu(title: "Terminal app", selection: intents.setting(\.terminalApp, from: state),
                                     options: installedTerminals.map { ($0, $0.title) })
                        .frame(width: Self.menuWidth)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear { syncThresholdText() }
        .onChange(of: settings.thresholds) { syncThresholdText() }
    }

    /// Matches the "Show timers" segmented control so every trailing control in the tab shares one width.
    private static let menuWidth: CGFloat = 270

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
                .frame(width: 56)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { commit() }
            Text("hours").font(Tokens.Typo.settingsBody).foregroundStyle(Tokens.Palette.settingsSecondary)
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
                        .frame(width: Tokens.Size.settingsControl, height: Tokens.Size.settingsControl)
                        .background(on ? Tokens.Palette.accent : .black.opacity(0.28), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}

/// Hour/minute field backed by minutes-after-midnight. A borderless `NSDatePicker` inside the settings field chrome:
/// SwiftUI's `.field` style draws its own bezel, shorter and darker than every other field in the window.
struct MinutePicker: View {
    let title: String
    @Binding var minute: Int

    var body: some View {
        TimeFieldRepresentable(minute: $minute)
            .fixedSize()
            // NSDatePicker's cell draws its text high and leaves extra room on the leading side; this optically
            // centers it in the field (measured from gallery captures).
            .offset(x: -3.75, y: 1.25)
            .settingsFieldChrome()
            .accessibilityLabel(title)
    }
}

private struct TimeFieldRepresentable: NSViewRepresentable {
    @Binding var minute: Int

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.textColor = .white
        picker.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        picker.focusRingType = .none
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.minute = $minute
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        if picker.dateValue != date { picker.dateValue = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(minute: $minute) }

    final class Coordinator: NSObject {
        var minute: Binding<Int>
        init(minute: Binding<Int>) { self.minute = minute }

        @objc func changed(_ picker: NSDatePicker) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
            minute.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}
