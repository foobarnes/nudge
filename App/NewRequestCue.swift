import AppKit
import NudgeCore

/// The sound half of the new-request cue, plus the reminder that repeats it (and the pill's jiggle) while new
/// requests go unopened. The pill animates itself from `newRequestPulse` and `reminderPulse`.
@MainActor
final class NewRequestCue {
    static let reminderInterval = 12.0 * 60
    private static let volume: Float = 0.4

    private let state: NudgeState
    private let notifications: NotificationService
    private let sound = NSSound(named: "Tink")?.copy() as? NSSound
    private var reminderTask: Task<Void, Never>?

    init(state: NudgeState, notifications: NotificationService) {
        self.state = state
        self.notifications = notifications
        sound?.volume = Self.volume
    }

    /// `isLooking` reports whether the card or dropdown is open, which counts as seeing a request the moment it lands.
    func start(isLooking: @escaping @MainActor () -> Bool) {
        var lastPulse = state.newRequestPulse
        observeChanges({ [state] in state.newRequestPulse }) { [weak self] pulse in
            guard let self, pulse > lastPulse else { return }
            lastPulse = pulse
            if isLooking() { return self.state.acknowledgeNewRows() }
            self.arrived()
        }
        observeChanges({ [state] in state.hasNewRows }) { [weak self] hasNew in
            if !hasNew { self?.reminderTask?.cancel() }
        }
    }

    private func arrived() {
        armReminder()
        guard state.settings.soundOnNewRequests else { return }
        Task {
            // The banner chimes on its own when notifications may play sounds; don't double up.
            if await notifications.bannersPlaySound() { return }
            play()
        }
    }

    /// Restarts the clock: the first reminder comes one interval after the latest arrival.
    private func armReminder() {
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.reminderInterval), tolerance: .seconds(10))
                guard !Task.isCancelled, let self else { return }
                self.remind()
            }
        }
    }

    /// Like red reminders, waits out off hours.
    private func remind() {
        guard state.hasNewRows, !state.isOffHours else { return }
        if state.settings.jiggleOnNewRequests { state.reminderPulse += 1 }
        if state.settings.soundOnNewRequests { play() }
    }

    private func play() {
        guard let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
