import AVFoundation
import AudioToolbox
import Foundation
import os

/// Playback state of the alarm audio pipeline.
///
/// Replaces the old `isPlaying: Bool` so the UI can distinguish between
/// "real audio is playing", "we tried but failed", and "stopped".
enum AudioPlaybackState: Equatable {
    /// Real audio (bundled file or synthetic tone) is looping.
    case playing

    /// AVAudioSession refused to activate — caller cannot guarantee any sound.
    /// Vibration is also skipped since without a session we have no playback path.
    case silentBecauseConfigFailed

    /// Bundled file existed but `AVAudioPlayer` rejected it (corrupt/format).
    /// Synthetic tone fallback also failed → only vibration is running.
    case vibrationOnly

    /// Initial state and after `stopAlarmSound()`.
    case stopped
}

/// Manages continuous alarm sound playback and vibration.
/// Configures AVAudioSession for playback even when screen is locked,
/// loops the alarm sound until explicitly stopped, and provides
/// a repeating vibration pattern via AudioToolbox.
final class AudioService {

    static let shared = AudioService()

    // MARK: - Notification names

    /// Posted whenever `state` transitions. Observers receive the new state in
    /// `userInfo[stateUserInfoKey]` so UI (e.g. AlarmFiringViewController) can
    /// surface a banner when audio falls back to vibration or fails entirely.
    ///
    /// Always posted on the main queue — observers can update UI without
    /// dispatching themselves.
    static let stateChangedNotification = Notification.Name("snoozepay.audio.stateChanged")
    static let stateUserInfoKey = "state"

    private var audioPlayer: AVAudioPlayer?
    private var vibrationTimer: Timer?

    /// Total seconds the fade-in ramp covers when `alarm.volumeFadeIn == true`
    /// (#150). Matches the design copy "За 30 секунд" exposed in the volume
    /// picker UI.
    private static let fadeInDuration: TimeInterval = 30

    /// Identifier of the alarm that currently owns the audio session.
    ///
    /// Set in `startAlarmSound(soundID:alarmID:)` and cleared in `stopAlarmSound()`.
    /// Callers that present a per-alarm UI (e.g. `AlarmFiringViewController`) check
    /// this value before calling `stopAlarmSound()` from `viewDidDisappear` so a
    /// dismissed firing screen does not silence audio that has already been
    /// claimed by the *next* alarm during a stacking-replace race (#116).
    private(set) var currentAlarmID: UUID?

    /// Current playback state. Mutating this also broadcasts a notification so
    /// callers can react to fallback paths (config failed / vibration only).
    private(set) var state: AudioPlaybackState = .stopped {
        didSet {
            guard oldValue != state else { return }
            NotificationCenter.default.post(
                name: Self.stateChangedNotification,
                object: self,
                userInfo: [Self.stateUserInfoKey: state]
            )
        }
    }

    /// Backwards-compatible boolean. `true` only when actually playing real audio.
    /// Retained so existing callers (AppDelegate guards, tests) keep working.
    var isPlaying: Bool { state == .playing }

    private init() {}

    // MARK: - Audio Session

    /// Configure the audio session for alarm playback.
    /// Uses `.playback` category so audio continues when screen is locked.
    /// - Throws: any underlying `AVAudioSession` error so the caller can decide
    ///   whether to fall back or surface the failure.
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.duckOthers])
        try session.setActive(true, options: [])
    }

    /// Deactivate the audio session when alarm is stopped.
    /// Failures are logged — there is no recovery path that the user could act on,
    /// but a stale session may keep other apps duck'ed.
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            AppLogger.audio.error("failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Alarm Sound

    /// Start playing alarm sound in a loop.
    /// - Parameters:
    ///   - soundID: Name of the sound file (without extension) in the app bundle.
    ///     Falls back to a system-generated tone if the file is missing or fails to load.
    ///   - alarmID: Identifier of the alarm taking ownership of the audio session.
    ///     Optional for callers that don't have a per-alarm context (legacy / tests).
    ///     Stored on `currentAlarmID` and cleared by `stopAlarmSound()`.
    ///   - volume: Per-alarm playback volume (#150). Clamped to `0...1`. Defaults
    ///     to `1.0` to preserve the historical "ring at full volume" behaviour
    ///     for callers that don't pass a volume.
    ///   - fadeIn: When `true`, ramps the player's `volume` from `0` to the
    ///     target `volume` over `fadeInDuration` seconds via
    ///     `AVAudioPlayer.setVolume(_:fadeDuration:)` (#150). Defaults to
    ///     `false` so legacy call sites keep their instant-on behaviour.
    func startAlarmSound(
        soundID: String,
        alarmID: UUID? = nil,
        volume: Float = 1.0,
        fadeIn: Bool = false
    ) {
        // Already in a non-stopped state — preserve the existing pipeline.
        // Earlier guard was `!isPlaying` (Bool); using state covers
        // `.vibrationOnly` and `.silentBecauseConfigFailed` so we don't try to
        // restart on top of a partial fallback either.
        guard state == .stopped else {
            handleStartWhileNonStopped(alarmID: alarmID)
            return
        }

        do {
            try configureAudioSession()
        } catch {
            // Audio session unavailable (e.g. another app holds it).
            // Cannot guarantee playback — skip vibration too and surface the
            // explicit fallback state so the UI can warn the user.
            AppLogger.audio.error("failed to configure audio session: \(error.localizedDescription, privacy: .public)")
            currentAlarmID = alarmID
            state = .silentBecauseConfigFailed
            return
        }

        let player = resolveAlarmPlayer(soundID: soundID)

        guard let player else {
            // Neither bundled file nor synthetic tone available — refuse to claim
            // playback. Vibration still runs so the user is at least woken.
            AppLogger.audio.notice("startAlarmSound: no audio source available, vibration only")
            currentAlarmID = alarmID
            state = .vibrationOnly
            startVibration()
            return
        }

        audioPlayer = player
        configurePlayerVolume(player, target: volume, fadeIn: fadeIn)

        // prepareToPlay returns Bool but does not throw; play() does not throw
        // either, but its return value indicates whether the queue accepted the
        // sound. A `false` here means we have a player object but the system
        // refused to start playback — surface that as `vibrationOnly` so the UI
        // does not silently swallow a real failure.
        let prepared = player.prepareToPlay()
        let started = player.play()
        if !prepared || !started {
            AppLogger.audio.error(
                "AVAudioPlayer play() rejected (prepared=\(prepared, privacy: .public), started=\(started, privacy: .public))"
            )
            audioPlayer = nil
            currentAlarmID = alarmID
            state = .vibrationOnly
            startVibration()
            return
        }

        currentAlarmID = alarmID
        state = .playing
        startVibration()
    }

    /// Handle an `.startAlarmSound` call while the service is already in a
    /// non-stopped state. Either transfers ownership to the new caller's
    /// `alarmID` (stacking-replace path #116) or logs a regression when no
    /// `alarmID` was passed. Pulled out of `startAlarmSound` so its body
    /// stays under SwiftLint's `function_body_length` cap (#182).
    private func handleStartWhileNonStopped(alarmID: UUID?) {
        // We're already playing — but the *caller* may be a new alarm taking
        // over (stacking-replace path #116). Update ownership so the previous
        // VC's `viewDidDisappear` correctly recognises the session no longer
        // belongs to it and skips `stopAlarmSound()`.
        if let alarmID {
            let previous = currentAlarmID
            currentAlarmID = alarmID
            let prevDesc = String(describing: previous)
            let stateDesc = String(describing: self.state)
            AppLogger.audio.notice(
                "ownership transfer \(prevDesc, privacy: .private) → \(alarmID, privacy: .private), state=\(stateDesc, privacy: .public)"
            )
        } else {
            // No alarmID provided while audio is already playing means the
            // existing owner is preserved. Log so a regression where a new
            // call site forgets to pass alarmID is diagnosable in Console.
            let stateDesc = String(describing: self.state)
            let ownerDesc = String(describing: self.currentAlarmID)
            AppLogger.audio.error(
                "missing alarmID while state=\(stateDesc, privacy: .public) — ownership NOT transferred, owner=\(ownerDesc, privacy: .private)"
            )
        }
    }

    /// Locate the bundled alarm sound (caf/m4a/wav/mp3 — in that order, with a
    /// `default_alarm` fallback) and try to wrap it in `AVAudioPlayer`. If the
    /// bundle hit fails or AVAudioPlayer rejects the file we fall back to the
    /// in-memory synthetic tone so the user still hears *something*.
    private func resolveAlarmPlayer(soundID: String) -> AVAudioPlayer? {
        let url: URL? = Bundle.main.url(forResource: soundID, withExtension: "caf")
            ?? Bundle.main.url(forResource: soundID, withExtension: "m4a")
            ?? Bundle.main.url(forResource: soundID, withExtension: "wav")
            ?? Bundle.main.url(forResource: soundID, withExtension: "mp3")
            ?? Bundle.main.url(forResource: "default_alarm", withExtension: "caf")
            ?? Bundle.main.url(forResource: "default_alarm", withExtension: "m4a")

        var player: AVAudioPlayer?
        if let soundURL = url {
            do {
                player = try AVAudioPlayer(contentsOf: soundURL)
            } catch {
                let name = soundURL.lastPathComponent
                let desc = error.localizedDescription
                AppLogger.audio.error(
                    "AVAudioPlayer init failed for \(name, privacy: .public): \(desc, privacy: .public)"
                )
                player = nil
            }
        }
        return player ?? Self.generateAlarmTone()
    }

    /// Apply per-alarm volume + optional fade-in. Defensive `min/max` clamp
    /// preserves the historical behaviour even when the caller hands us a
    /// NaN/Inf value (a corrupt payload still produces a playable alarm).
    private func configurePlayerVolume(_ player: AVAudioPlayer, target volume: Float, fadeIn: Bool) {
        player.numberOfLoops = -1
        let clampedVolume = min(max(volume.isFinite ? volume : 1.0, 0), 1)
        if fadeIn {
            // Start at 0 and ramp up so the user is woken gently. AVAudio
            // schedules the ramp on the audio thread and survives screen
            // lock — no Timer needed.
            player.volume = 0
            player.setVolume(clampedVolume, fadeDuration: Self.fadeInDuration)
        } else {
            player.volume = clampedVolume
        }
    }

    /// Stop alarm sound and vibration immediately.
    func stopAlarmSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopVibration()
        deactivateAudioSession()
        currentAlarmID = nil
        state = .stopped
    }

    // MARK: - Pause / Resume
    //
    // The firing-time top-up flow (#141) needs to silence the alarm while a
    // bottom sheet is open without losing the audio session — `stopAlarmSound`
    // tears the session down which would force a fresh permission check on
    // resume and break the `currentAlarmID` ownership tracking that #116
    // depends on. `pauseAlarmSound` instead pauses the player + stops the
    // vibration timer, leaving `state` and `currentAlarmID` intact so a
    // subsequent `resumeAlarmSound()` can keep playing on the same session.

    /// Pause looped playback + vibration without releasing the audio session.
    /// No-op if no audio is currently owned (state != .playing). Used by the
    /// firing-time top-up sheet (#141) so the alarm goes quiet while the user
    /// completes Apple Pay, then resumes if they cancel or the 60s auto-resume
    /// timer fires. Does not change `state` — observers continue to see
    /// `.playing` because the session is still owned and the next `resume()`
    /// must succeed without re-asking for it.
    func pauseAlarmSound() {
        guard state == .playing else { return }
        audioPlayer?.pause()
        stopVibration()
    }

    /// Resume playback + vibration after `pauseAlarmSound()`. No-op if no
    /// player exists (state != .playing). Idempotent so the bottom sheet's
    /// dismiss path can call it without checking pause state first.
    func resumeAlarmSound() {
        guard state == .playing, let player = audioPlayer else { return }
        // `play()` returns false only if the queue refuses — which on a paused
        // looping player should not happen unless the session was deactivated
        // out-of-band. Log so a regression where pause/resume gets out of sync
        // (e.g. interrupted by another app's audio) is diagnosable.
        if !player.play() {
            AppLogger.audio.error("resumeAlarmSound: AVAudioPlayer.play() returned false")
        }
        startVibration()
    }

    // MARK: - Vibration

    /// Start a repeating vibration pattern (vibrate every ~1 second).
    private func startVibration() {
        stopVibration()

        // Trigger first vibration immediately
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        // Repeat vibration on a timer
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    /// Stop the vibration timer.
    private func stopVibration() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }

    // MARK: - Tone Generation
    //
    // The synthetic-tone generator + WAV packer + binary helpers live in
    // `AudioService+Tone.swift` (#182) so this file stays under SwiftLint's
    // `file_length` cap. `resolveAlarmPlayer` calls
    // `Self.generateAlarmTone()` exactly as before — only the physical
    // location moved.
}
