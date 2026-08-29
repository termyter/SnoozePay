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
    /// Notification is posted on the main queue by the service, so no extra
    /// hop is needed.
    func observeAudioState() {
        audioStateObserver = NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let newState = note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState
            else { return }
            self.applyAudioState(newState)
        }
    }

    /// Surface (or hide) the warning banner depending on AudioService state.
    /// Decoupled from `observeAudioState` so we can call it once after
    /// `startAlarmSound` to catch the synchronous initial transition.
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
