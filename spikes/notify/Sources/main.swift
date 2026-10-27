// Spike 2: agent app + UNUserNotificationCenter category actions
// (+ Terminal.app Automation prompt for this bundle on "Open").
import AppKit
import UserNotifications
import os

let logger = Logger(subsystem: "io.github.foobarnes.nudge.spike-notify", category: "spike")
let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NudgeSpike")
let logURL = logDir.appendingPathComponent("notify.log")

func log(_ msg: String) {
    logger.notice("\(msg, privacy: .public)")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        log("launched bundle=\(Bundle.main.bundlePath)")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "N0"
        let menu = NSMenu()
        let postItem = menu.addItem(withTitle: "Post notification", action: #selector(post), keyEquivalent: "")
        postItem.target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        statusItem = item

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(
            identifier: "REVIEW_REQUEST",
            actions: [UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground]),
                      UNNotificationAction(identifier: "SNOOZE_1H", title: "Snooze 1h", options: [])],
            intentIdentifiers: [])])
        Task { @MainActor in
            await logSettings("before-request")
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                log("requestAuthorization granted=\(granted)")
            } catch {
                log("requestAuthorization error=\(error)")
            }
            await logSettings("after-request")
            post()
        }
    }

    func logSettings(_ tag: String) async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        log("\(tag) authorizationStatus=\(s.authorizationStatus.rawValue) alertStyle=\(s.alertStyle.rawValue)")
    }

    @objc func post() {
        let content = UNMutableNotificationContent()
        content.title = "alice requested your review"
        content.body = "acme/api#4211 · Fix token refresh"
        content.categoryIdentifier = "REVIEW_REQUEST"
        content.userInfo = ["url": "https://github.com/acme/api/pull/4211"]
        // Same identifier on repeat posts: should replace, not duplicate.
        let req = UNNotificationRequest(identifier: "RRE_example", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in log("posted err=\(String(describing: err))") }
    }

    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async
        -> UNNotificationPresentationOptions {
        log("willPresent id=\(n.request.identifier)")
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let action = r.actionIdentifier
        log("didReceive action=\(action) id=\(r.notification.request.identifier)")
        if action == "OPEN" {
            await runTerminal()
        }
    }

    @MainActor func runTerminal() {
        let marker = logDir.appendingPathComponent("terminal-marker").path
        let src = "tell application \"Terminal\" to do script \"/bin/zsh -lc \" & quoted form of \"date > \(marker); exit\""
        var err: NSDictionary?
        _ = NSAppleScript(source: src)?.executeAndReturnError(&err)
        log("terminal do script error=\(err.map { "\($0)" } ?? "nil")")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
