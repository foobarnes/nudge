import AppKit
import NudgeCore
import NudgeUI
import SwiftUI

// Dev harness: `swift run NudgeGallery [-scene <name>] [-dark] [-shot] [-fast] [-slow] [-notKey]`.
// Prints "WINDOW <number>" once shown, for `screencapture -l <number>`. Menus and popovers are opened by hand.
// `-slow` runs the pill morph at 1/8 speed (frame inspection); `-notKey` hands key status to a helper window so
// glass can be compared key vs. not key. The morph* scenes toggle the pill every 2.5s in each anchor corner.

@main
struct GalleryApp: App {
    @NSApplicationDelegateAdaptor(GalleryDelegate.self) private var delegate
    @State private var scene = Scene.initial

    var body: some SwiftUI.Scene {
        Window("Nudge Gallery", id: "gallery") {
            GalleryView(scene: $scene)
                .onAppear { delegate.install() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

enum Scene: String, CaseIterable, Identifiable {
    case pillMixed, pillFresh, pillAmber, pillRed, pillTeam, pillOffHours, pillStale, pillAuthError, pillAllClear,
         pillCheck, pillDimmed, pillLoading, pillExpanded, pillExpandedBottom, pillExpandedSnoozed, pillExpandedNotice
    case dropdown, dropdownSnoozed, dropdownEmpty, dropdownAuthError, dropdownNotice
    case rowRest, rowHovered, rowHoveredLabels, hoverCards, workTimePopover, snoozeMenu
    case settingsGeneral, settingsNotifications, settingsActions, settingsAbout
    case morphTopTrailing, morphTopLeading, morphBottomTrailing, morphBottomLeading

    var id: String { rawValue }

    var isMorph: Bool { rawValue.hasPrefix("morph") }

    var anchor: Alignment {
        switch self {
        case .morphTopLeading: .topLeading
        case .morphBottomTrailing: .bottomTrailing
        case .morphBottomLeading, .pillExpandedBottom: .bottomLeading
        default: .topTrailing
        }
    }

    static var initial: Scene {
        let name = UserDefaults.standard.string(forKey: "scene") ?? ""
        return Scene(rawValue: name) ?? .pillMixed
    }

    var size: CGSize {
        switch self {
        case .pillExpanded, .pillExpandedBottom, .pillExpandedSnoozed, .pillExpandedNotice,
             .morphTopTrailing, .morphTopLeading, .morphBottomTrailing, .morphBottomLeading: CGSize(width: 520, height: 540)
        case .dropdown, .dropdownSnoozed, .dropdownEmpty, .dropdownAuthError, .dropdownNotice: CGSize(width: 460, height: 660)
        case .rowRest, .rowHovered, .rowHoveredLabels: CGSize(width: 460, height: 200)
        case .hoverCards: CGSize(width: 460, height: 440)
        case .workTimePopover, .snoozeMenu: CGSize(width: 440, height: 360)
        case .settingsGeneral, .settingsNotifications, .settingsActions, .settingsAbout: CGSize(width: 1000, height: 720)
        default: CGSize(width: 420, height: 180)
        }
    }

    /// Dark wallpaper for the settings scenes, off hours, and every scene under `-dark` so dark-mode contrast is real.
    var wallpaperIsDark: Bool {
        if ProcessInfo.processInfo.arguments.contains("-dark") { return true }
        return switch self {
        case .settingsGeneral, .settingsNotifications, .settingsActions, .settingsAbout, .pillOffHours: true
        default: false
        }
    }
}

struct GalleryView: View {
    @Binding var scene: Scene
    @State private var state = NudgeState.sample(.mixed)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper(dark: scene.wallpaperIsDark)
            content
            Picker("Scene", selection: $scene) {
                ForEach(Scene.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 180)
            .padding(8)
            .opacity(ProcessInfo.processInfo.arguments.contains("-shot") ? 0 : 1)
        }
        .frame(width: scene.size.width, height: scene.size.height)
        .environment(\.pillMotionScale, ProcessInfo.processInfo.arguments.contains("-slow") ? 8 : 1)
        .onChange(of: scene, initial: true) { _, scene in state = Self.state(for: scene) }
        .task(id: scene) {
            guard scene.isMorph else { return }
            let slow = ProcessInfo.processInfo.arguments.contains("-slow")
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(slow ? 20_000 : 2500))
                state.pillExpanded.toggle()
                print("TOGGLE expanded=\(state.pillExpanded)")   // frame captures are timed from this line
                fflush(stdout)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case .pillMixed, .pillFresh, .pillAmber, .pillRed, .pillTeam, .pillOffHours, .pillStale, .pillAuthError,
             .pillAllClear, .pillCheck, .pillDimmed, .pillLoading, .pillExpanded, .pillExpandedBottom,
             .pillExpandedSnoozed, .pillExpandedNotice:
            pill
        case .morphTopTrailing, .morphTopLeading, .morphBottomTrailing, .morphBottomLeading:
            pill
        case .dropdown, .dropdownSnoozed, .dropdownEmpty, .dropdownAuthError, .dropdownNotice:
            DropdownView(state: state, intents: intents).padding(8)
        case .rowRest, .rowHovered, .rowHoveredLabels:
            glassPanel {
                GalleryViews.row(state.rows[1], state: state, intents: intents, revealed: scene != .rowRest)
                GalleryViews.row(state.rows[3], state: state, intents: intents, revealed: false)
            }
            .environment(\.visibleMiniLabel, scene == .rowHoveredLabels ? "Hide until re-requested" : nil)
        case .hoverCards:
            VStack(spacing: 16) {
                glassCard { GalleryViews.hoverCard(SampleRows.longTitle(now: .now), intents: intents) }
                glassCard { GalleryViews.hoverCard(SampleRows.teamWithOthers(now: .now), intents: intents) }
            }
            .padding(24)
        case .workTimePopover:
            glassCard { GalleryViews.workTimePopover(state: state) }.padding(24)
        case .snoozeMenu:
            glassCard { GalleryViews.snoozeMenu(state: state, intents: intents) }.padding(24)
        case .settingsGeneral, .settingsNotifications, .settingsActions, .settingsAbout:
            SettingsRootView(state: state, intents: intents, initialTab: tab).padding(24)
        }
    }

    /// The pill's layout size is always its card size; an overlay keeps its anchor corner in place even when the
    /// scene is smaller than that (the shell's window root works the same way).
    private var pill: some View {
        Color.clear
            .overlay(alignment: scene.anchor) { PillView(state: state, intents: intents, anchor: scene.anchor) }
            .padding(24)
    }

    private func glassPanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 2, content: content)
            .padding(10)
            .frame(width: 380)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            .padding(24)
    }

    private func glassCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var tab: SettingsTab {
        switch scene {
        case .settingsNotifications: .notifications
        case .settingsActions: .actions
        case .settingsAbout: .about
        default: .general
        }
    }

    private var intents: NudgeIntents {
        NudgeIntents(
            snooze: { row, option in
                state.rows.removeAll { $0.id == row.id }
                let until = SnoozeParser.resolve(option, now: .now, config: state.settings.workHours) ?? .now
                state.snoozedRows.append(SampleRows.snoozed(row, until: until))
            },
            unsnooze: { row in
                state.snoozedRows.removeAll { $0.id == row.id }
                state.rows.append(row)
            },
            hide: { row in state.rows.removeAll { $0.id == row.id } },
            updateSettings: { change in change(&state.settings) })
    }

    @MainActor private static func state(for scene: Scene) -> NudgeState {
        let s: NudgeState
        switch scene {
        case .pillFresh: s = .sample(.fresh)
        case .pillAmber: s = .sample(.amber)
        case .pillTeam: s = .sample(.teamOnly)
        case .pillOffHours: s = .sample(.offHours)
        case .pillStale: s = .sample(.stale)
        case .pillAuthError, .dropdownAuthError: s = .sample(.authError)
        case .pillAllClear: s = .sample(.empty)
        case .pillCheck:
            s = .sample(.empty)
            s.settings.displayMode = .widgetAlways
        case .pillDimmed:
            s = .sample(.mixed)
            s.pillDimmed = true
        case .pillLoading: s = .sample(.loading)
        case .pillExpanded:
            s = .sample(.mixed)
            s.pillExpanded = true
        case .pillExpandedBottom, .morphBottomTrailing, .morphBottomLeading:
            s = .sample(.mixed)
            s.pillExpanded = scene == .pillExpandedBottom
            s.pillEdge = .bottom
        case .pillExpandedSnoozed:
            s = .sample(.snoozed)
            s.pillExpanded = true
        case .pillExpandedNotice:
            s = .sample(.notice)
            s.pillExpanded = true
        case .dropdownSnoozed: s = .sample(.snoozed)
        case .dropdownEmpty: s = .sample(.empty)
        case .dropdownNotice: s = .sample(.notice)
        default: s = .sample(.mixed)
        }
        return s
    }
}

struct Wallpaper: View {
    let dark: Bool

    var body: some View {
        ZStack {
            Color(dark ? Color(hex: 0x141824) : Color(hex: 0x9FB2C4))
            RadialGradient(colors: [dark ? Color(hex: 0x3D6FB6) : Color(hex: 0xC7B9A8), .clear],
                           center: .init(x: 0.18, y: 0.8), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [dark ? Color(hex: 0xD0703F) : Color(hex: 0x6F88A4), .clear],
                           center: .init(x: 0.82, y: 0.2), startRadius: 0, endRadius: 420)
            if !dark {
                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.78))
                    .frame(width: 300, height: 220).offset(x: -120, y: 60)
            }
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

@MainActor
final class GalleryDelegate: NSObject, NSApplicationDelegate {
    private var installed = false
    private var keyHolder: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let dark = ProcessInfo.processInfo.arguments.contains("-dark")
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    func install() {
        guard !installed else { return }
        installed = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(ProcessInfo.processInfo.arguments.contains("-fast") ? 250 : 700))
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            window.makeKeyAndOrderFront(nil)
            if ProcessInfo.processInfo.arguments.contains("-notKey") {
                // A helper window takes key status so the gallery window renders its glass as inactive.
                let helper = NSWindow(contentRect: NSRect(x: window.frame.minX, y: window.frame.minY - 60, width: 120, height: 40),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                helper.title = "key holder"
                helper.makeKeyAndOrderFront(nil)
                keyHolder = helper
            }
            let fast = ProcessInfo.processInfo.arguments.contains("-fast")
            try? await Task.sleep(for: .milliseconds(fast ? 150 : 1200))
            print("WINDOW \(window.windowNumber)")
            fflush(stdout)
        }
    }
}
