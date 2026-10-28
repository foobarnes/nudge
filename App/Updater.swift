import AppKit
import Sparkle

/// Sparkle updates for release builds. The feed URL and public key come from Info.plist; local builds have no key,
/// so the updater stays off and never replaces a dev build.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var isEnabled: Bool { controller != nil }

    /// Activates first: Nudge is a menu bar app, so Sparkle's modal alert would otherwise open behind other apps'
    /// windows and swallow every click in Nudge until it's found.
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// A menu bar app rarely quits, so an update downloaded in the background would wait forever for "install on
    /// quit". Install and relaunch right away instead; it takes about a second.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstallHandler()
        return true
    }
}
