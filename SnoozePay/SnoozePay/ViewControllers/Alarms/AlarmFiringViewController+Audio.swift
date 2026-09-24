import UIKit
import os

/// AudioService observation + warning-banner mapping for the firing screen.
///
/// Split out from `AlarmFiringViewController` so the main file fits the
/// `file_length` cap. The banner copy and the .silentBecauseConfigFailed /
/// .vibrationOnly mappings live here unchanged from the pre-Dawn version
/// (#77 / #116) — the visual rework in #138 deliberately preserves the
/// text and the placement above the snooze CTA.
extension AlarmFiringViewController {

    /// Wire `AudioService.stateChangedNotification` → `applyAudioState`.
    /// The service posts from `DispatchQueue.main.async`, outside its serial
    /// queue (#848), so the block already runs on main; `queue: .main` only
    /// states that. The post trails the transition, which is why `viewDidLoad`
    /// also applies the state it reads back right after `startAlarmSound`.
    ///
    /// Only notes about this screen's alarm are applied (#851), see
    /// `isAudioNoteAboutThisAlarm`.
    func observeAudioState() {
        audioStateObserver = NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                self.isAudioNoteAboutThisAlarm(note.userInfo?[AudioService.alarmIDUserInfoKey] as? UUID),
                let newState = note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState
            else { return }
            self.applyAudioState(newState)
        }
    }

    /// Whether a state note naming `alarmID` is about this screen (#851).
    ///
    /// The posts are asynchronous, so the `.stopped` that screen A queues on
    /// dismiss can land on screen B after B registered, and hide B's banner
    /// while B's sound is failing. A note about another alarm is dropped.
    ///
    /// A note naming no alarm is dropped too, on purpose. It means no alarm
    /// owned the sound (a start without `alarmID`), and the banner speaks only
    /// for this alarm's sound. This screen always starts its sound with its
    /// own id, and on the AlarmKit path the system rings, not `AudioService`.
    /// Dropping costs nothing: `viewDidLoad` reads the state back directly.
    func isAudioNoteAboutThisAlarm(_ alarmID: UUID?) -> Bool {
        alarmID == viewModel.alarm.id
    }

    /// Surface (or hide) the warning banner depending on AudioService state.
    /// Decoupled from `observeAudioState` so we can call it once after
    /// `startAlarmSound`: the banner is right before the first frame instead
    /// of one main-queue turn later, when the notification lands. The late
    /// notification then re-applies the same state, which is harmless.
    func applyAudioState(_ newState: AudioPlaybackState) {
        switch newState {
        case .playing, .stopped:
            audioWarningBanner.isHidden = true
            audioWarningBanner.text = nil
            audioWarningBanner.accessibilityLabel = nil
        case .silentBecauseConfigFailed:
            let text = Localized.text("firing.audio.config_failed")
            audioWarningBanner.text = "  \(text)  "
            audioWarningBanner.accessibilityLabel = text
            audioWarningBanner.isHidden = false
        case .vibrationOnly:
            let text = Localized.text("firing.audio.vibration_only")
            audioWarningBanner.text = "  \(text)  "
            audioWarningBanner.accessibilityLabel = text
            audioWarningBanner.isHidden = false
        }
    }
}
