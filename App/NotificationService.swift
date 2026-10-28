import AppKit
import NudgeCore
import UserNotifications

/// Posts the engine's planned banners and the shell's own alerts, and routes banner actions back to intents.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    enum Action: String {
        case open = "OPEN"
        case snooze1h = "SNOOZE_1H"
        case snoozeTomorrow = "SNOOZE_TOMORROW"
        case snoozeFor = "SNOOZE_FOR"
        case startReview = "START_REVIEW"
    }

    static let reviewCategory = "REVIEW_REQUEST"
    nonisolated private static let rowKey = "rowID"
    nonisolated private static let urlKey = "url"

    private let state: NudgeState
    private let center = UNUserNotificationCenter.current()
    private var engine: NudgeEngine?
    private var intents = NudgeIntents()

    init(state: NudgeState) {
        self.state = state
        super.init()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(
            identifier: Self.reviewCategory,
            actions: [
                UNNotificationAction(identifier: Action.open.rawValue, title: "Open", options: [.foreground]),
                UNNotificationAction(identifier: Action.snooze1h.rawValue, title: "Snooze 1h"),
                UNNotificationAction(identifier: Action.snoozeTomorrow.rawValue, title: "Snooze until tomorrow"),
                UNTextInputNotificationAction(identifier: Action.snoozeFor.rawValue, title: "Snooze for…",
                                              textInputButtonTitle: "Snooze", textInputPlaceholder: "2h, 4pm, mon"),
                UNNotificationAction(identifier: Action.startReview.rawValue, title: "Start review"),
            ],
            intentIdentifiers: [])])
    }

    func connect(engine: NudgeEngine, intents: NudgeIntents) {
        self.engine = engine
        self.intents = intents
    }

    /// Asked from `applicationDidFinishLaunching`; an `.accessory` app gets the prompt without activating.
    func authorize() {
        Task {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) } catch {
                NSLog("Nudge: notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    func post(_ planned: PlannedNotification) {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        switch planned.kind {
        case .newRequest, .redReminder:
            content.categoryIdentifier = Self.reviewCategory
            content.sound = .default
        case .authProblem, .actionFailed:
            break
        }
        var info: [String: String] = [:]
        info[Self.rowKey] = planned.rowID
        info[Self.urlKey] = planned.url?.absoluteString
        content.userInfo = info
        // Identifier = request key, so a repeat post replaces the banner instead of stacking.
        center.add(UNNotificationRequest(identifier: planned.id, content: content, trigger: nil))
    }

    /// A shell-originated banner without actions (action failures, permissions, unreadable snooze text).
    func alert(title: String, body: String, url: URL? = nil, id: String = UUID().uuidString) {
        post(PlannedNotification(id: id, kind: .actionFailed, title: title, body: body, rowID: nil, url: url))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let rowID = info[Self.rowKey] as? String
        let url = (info[Self.urlKey] as? String).flatMap(URL.init(string:))
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await handle(action: action, rowID: rowID, url: url, text: text)
    }

    private func handle(action: String, rowID: String?, url: URL?, text: String?) {
        let row = rowID.flatMap { engine?.row(withID: $0) }
        guard let row else {
            // The row is gone (reviewed, hidden) or this banner isn't about a row: just open its link.
            if action == UNNotificationDefaultActionIdentifier || action == Action.open.rawValue, let url {
                NSWorkspace.shared.open(url)
            }
            return
        }
        switch Action(rawValue: action) {
        case .open: intents.open(row)
        case .snooze1h: intents.snooze(row, .minutes(60))
        case .snoozeTomorrow: intents.snooze(row, .untilTomorrow)
        case .startReview: intents.startReview(row, nil)
        case .snoozeFor: snooze(row, text: text ?? "")
        case nil: if action == UNNotificationDefaultActionIdentifier { intents.open(row) }
        }
    }

    private func snooze(_ row: PRRow, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let until = SnoozeParser.parse(trimmed, now: .now, config: state.settings.workHours) else {
            alert(title: "Couldn't read “\(trimmed)”", body: "Try 45m, 2h, 4pm, tomorrow, or mon.")
            return
        }
        intents.snooze(row, .until(until))
        intents.updateSettings { $0.lastCustomSnoozeText = trimmed }
    }
}
