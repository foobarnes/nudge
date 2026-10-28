import AppKit
import NudgeCore
import Sparkle

/// Sparkle updates for release builds. The feed URL and public key come from Info.plist; local builds have no key,
/// so the updater stays off and never replaces a dev build.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private let state: NudgeState

    init(state: NudgeState) {
        self.state = state
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        state.updates = UpdateStatus(lastChecked: controller.updater.lastUpdateCheckDate,
                                     checksAutomatically: controller.updater.automaticallyChecksForUpdates)
    }

    var isEnabled: Bool { controller != nil }

    /// Activates first: Nudge is a menu bar app, so Sparkle's modal alert would otherwise open behind other apps'
    /// windows and swallow every click in Nudge until it's found.
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// Settings → About: checks without Sparkle's alerts and reports into `state.updates`. Installing goes through
    /// `checkForUpdates()`, which shows Sparkle's own prompt for the update found here.
    func checkForUpdateInformation() {
        guard let updater = controller?.updater, updater.canCheckForUpdates else { return }
        state.updates?.phase = .checking
        updater.checkForUpdateInformation()
    }

    func setChecksAutomatically(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
        state.updates?.checksAutomatically = on
    }

    /// A menu bar app rarely quits, so an update downloaded in the background would wait forever for "install on
    /// quit". Install and relaunch right away instead; it takes about a second.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstallHandler()
        return true
    }

    // Every check reports here, including the hourly background one and the menu's "Check for Updates…".

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { state.updates?.phase = .available(version: version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        MainActor.assumeIsolated { state.updates?.phase = .upToDate }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let error = error as NSError?
        let benign: Set<Int> = [Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue)]
        let message = error.flatMap { benign.contains($0.code) ? nil : $0.localizedDescription }
        MainActor.assumeIsolated {
            guard var updates = state.updates else { return }
            if let message {
                updates.phase = .failed(message: message)
            } else {
                updates.lastChecked = .now
                if updates.phase == .checking { updates.phase = .idle }
            }
            state.updates = updates
        }
    }
}
