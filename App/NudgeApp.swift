import AppKit
import NudgeCore
import NudgeUI
import SwiftUI

// Skeleton entry point. The AppKit shell (AppDelegate, panels, status item) replaces the body.
@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "clock.badge", accessibilityDescription: "Nudge")
        statusItem = item
    }
}
