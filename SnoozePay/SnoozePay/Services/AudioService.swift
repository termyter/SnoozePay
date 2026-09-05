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
    /// Posted synchronously from the service's internal serial queue — UI
    /// observers must subscribe with `queue: .main` (as
    /// `AlarmFiringViewController.observeAudioState` does) before touching views.
    static let stateChangedNotification = Notification.Name("snoozepay.audio.stateChanged")
    static let stateUserInfoKey = "state"

    /// Posted when a RESUME re-activates the audio session and that
    /// re-activation FAILS (`resumePlaybackLocked` → `.silentBecauseConfigFailed`).
    /// Unlike `stateChangedNotification`, which only the on-screen firing VC
    /// observes, this is consumed by `AppDelegate` to post a time-sensitive
    /// local notification — so a silent failed wake is surfaced even when no
    /// firing screen is visible (locked-screen wake / AlarmKit path / top-up
    /// sheet on top). See `AlarmFiringViewController` for the in-app banner that
    /// still covers the on-screen case (#405).
    static let resumeAudioFailedNotification = Notification.Name("snoozepay.audio.resumeFailed")

    /// Serializes every read/write of the mutable fields below (#202).
    /// `startAlarmSound` can arrive on a UN-delegate background thread while
    /// `stopAlarmSound` runs on main — without this queue the four fields can
    /// land in inconsistent combinations (e.g. `.playing` with a nil player).
    /// Mirrors the pattern in `BalanceService` / `AlarmRepository`.
    private let queue = DispatchQueue(label: "com.snoozepay.audio.serial")

    /// Queue-confined. Only touch from inside `queue`.
    private var audioPlayer: AVAudioPlayer?

    /// Queue-confined storage; the timer itself is installed on the *main* run
    /// loop (see `startVibration`) so it keeps firing regardless of which
    /// thread started the alarm (#202).
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
    var currentAlarmID: UUID? { queue.sync { _currentAlarmID } }

    /// Queue-confined backing storage for `currentAlarmID`.
    private var _currentAlarmID: UUID?

    /// Queue-confined count of successful `configureAudioSession()` activations.
    /// Exposed (`@testable`) so unit tests can assert that a resume path actually
    /// reclaims the session before `play()` (#395) — the activation itself can't
    /// be observed in the simulator, but the call count proves the code path ran.
    private var _sessionActivationCount = 0

    /// Test-only snapshot of how many times the audio session was (re)activated.
    /// Thread-safe read; see `_sessionActivationCount`.
    var sessionActivationCount: Int { queue.sync { _sessionActivationCount } }

    /// Queue-confined. `true` while the looped player is paused but the session
    /// is still owned — either the top-up sheet paused it (#141) or a system
    /// interruption did (#374). `_state` stays `.playing` throughout (the
    /// session is ours and a resume must succeed without re-asking), so this
    /// flag is what distinguishes "audible right now" from "owned but silent".
    private var _isPaused = false

    /// Queue-confined. `true` when the current pause was caused by an
    /// `AVAudioSession` interruption (call/Siri) and should therefore
    /// auto-resume when the interruption ends — as opposed to a top-up pause,
    /// which only resumes via `resumeAlarmSound()` (#374).
    private var _interrupted = false

    /// Current playback state. Thread-safe snapshot read (#202).
    var state: AudioPlaybackState { queue.sync { _state } }

    /// Queue-confined backing storage for `state`. Mutating this also
    /// broadcasts a notification so callers can react to fallback paths
    /// (config failed / vibration only). The post happens synchronously on
    /// the serial queue — see `stateChangedNotification` docs.
    private var _state: AudioPlaybackState = .stopped {
        didSet {
            guard oldValue != _state else { return }
            NotificationCenter.default.post(
                name: Self.stateChangedNotification,
                object: self,
                userInfo: [Self.stateUserInfoKey: _state]
            )
        }
    }

    /// Backwards-compatible boolean. `true` only when actually playing real audio.
    /// Retained so existing callers (AppDelegate guards, tests) keep working.
    /// Note: stays `true` across a pause/interruption (the session is still
    /// owned) — use `isPaused` to tell whether sound is *audible right now*.
    var isPlaying: Bool { state == .playing }

    /// `true` while owned audio is paused (top-up sheet #141 or interruption
    /// #374). Callers that need "is sound actually audible" check
    /// `isPlaying && !isPaused`. Thread-safe snapshot read.
    var isPaused: Bool { queue.sync { _isPaused } }

    private init() {
        // Resume the alarm after a phone call / Siri interruption — for an
        // alarm a permanent silence is a failed wake, so we re-activate and
        // restart rather than waiting for the user (#374). The singleton lives
        // for the app's lifetime, so the observer never needs removal.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // MARK: - Audio Session

    /// Configure the audio session for alarm playback.
    /// Uses `.playback` category so audio continues when screen is locked.
    /// - Throws: any underlying `AVAudioSession` error so the caller can decide
    ///   whether to fall back or surface the failure.
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.duckOthers])
        try session.setActive(true, options: [])
        // Only counted on success (a throw skips this) — see `sessionActivationCount`.
        _sessionActivationCount += 1
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
        // Hop through the serial queue so concurrent start/stop calls (UN
        // delegate background thread vs main) cannot interleave field writes (#202).
        queue.sync {
            startAlarmSoundLocked(soundID: soundID, alarmID: alarmID, volume: volume, fadeIn: fadeIn)
        }
    }

    /// Queue-confined body of `startAlarmSound`. Must only be called from `queue`.
    private func startAlarmSoundLocked(
        soundID: String,
        alarmID: UUID?,
        volume: Float,
        fadeIn: Bool
    ) {
        // Already in a non-stopped state — preserve the existing pipeline.
        // Earlier guard was `!isPlaying` (Bool); using state covers
        // `.vibrationOnly` and `.silentBecauseConfigFailed` so we don't try to
        // restart on top of a partial fallback either.
        guard _state == .stopped else {
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
            _currentAlarmID = alarmID
            _state = .silentBecauseConfigFailed
            return
        }

        let player = resolveAlarmPlayer(soundID: soundID)

        guard let player else {
            // Neither bundled file nor synthetic tone available — refuse to claim
            // playback. Vibration still runs so the user is at least woken.
            AppLogger.audio.notice("startAlarmSound: no audio source available, vibration only")
            _currentAlarmID = alarmID
            _state = .vibrationOnly
            startVibration()
            return
        }

        // Fresh start always begins audible; clear any stale pause/interrupt
        // bookkeeping (defensive — we only reach here from `.stopped`).
        _isPaused = false
        _interrupted = false
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
            _currentAlarmID = alarmID
            _state = .vibrationOnly
            startVibration()
            return
        }

        _currentAlarmID = alarmID
        _state = .playing
        startVibration()
    }

    /// Handle an `.startAlarmSound` call while the service is already in a
    /// non-stopped state. Either transfers ownership to the new caller's
    /// `alarmID` (stacking-replace path #116) or logs a regression when no
    /// `alarmID` was passed. Pulled out of `startAlarmSound` so its body
    /// stays under SwiftLint's `function_body_length` cap (#182).
    /// Must only be called from `queue`.
    private func handleStartWhileNonStopped(alarmID: UUID?) {
        // If the session is paused (top-up sheet open #141, or mid-interruption
        // #374) a newly firing alarm would otherwise stay silent until the
        // top-up auto-resume — un-pause now so the incoming alarm is immediately
        // audible on the already-owned session, consistent with #116's
        // "audio is already ringing, just hand over ownership" philosophy.
        if _isPaused {
            resumePlaybackLocked()
        }

        // We're already playing — but the *caller* may be a new alarm taking
        // over (stacking-replace path #116). Update ownership so the previous
        // VC's `viewDidDisappear` correctly recognises the session no longer
        // belongs to it and skips `stopAlarmSound()`.
        if let alarmID {
            let previous = _currentAlarmID
            _currentAlarmID = alarmID
            let prevDesc = String(describing: previous)
            let stateDesc = String(describing: self._state)
            AppLogger.audio.notice(
                "ownership transfer \(prevDesc, privacy: .private) → \(alarmID, privacy: .private), state=\(stateDesc, privacy: .public)"
            )
        } else {
            // No alarmID provided while audio is already playing means the
            // existing owner is preserved. Log so a regression where a new
            // call site forgets to pass alarmID is diagnosable in Console.
            let stateDesc = String(describing: self._state)
            let ownerDesc = String(describing: self._currentAlarmID)
            AppLogger.audio.error(
                "missing alarmID while state=\(stateDesc, privacy: .public) — ownership NOT transferred, owner=\(ownerDesc, privacy: .private)"
            )
        }
    }

    /// Sound looked up when the requested `soundID` has no bundled file. Same
    /// name as `AlarmScheduler.fallbackSoundID` and deliberately a separate
    /// constant: the two resolve through different APIs (`Bundle.url` here, a
    /// file name handed to AlarmKit there), so tying them together would say
    /// they must stay equal, which nothing requires.
    static let fallbackSoundID = "default_alarm"

    /// Extensions tried, in order, for both the requested sound and the
    /// fallback. Part of the diagnostic: naming which extensions were tried is
    /// what separates "the file is missing" from "the file is there under an
    /// extension this list does not know".
    ///
    /// The pre-#765 `??` chain tried all four for `soundID` but only
    /// `caf`/`m4a` for the fallback. Unified, so the two lookups cannot
    /// disagree about what counts as a sound file. The bundle ships
    /// `default_alarm.caf`, which the old chain already found first — the widening
    /// changes nothing that is shipped.
    static let alarmSoundExtensions = ["caf", "m4a", "wav", "mp3"]

    /// Log identifier for a `soundID` with no bundled file, where
    /// ``fallbackSoundID`` still answered. The alarm rings a real sound — one
    /// the user did not choose.
    static var missingSoundErrorID: String { "AUDIO-765-SOUND-MISSING" }

    /// Log identifier for a lookup that found neither the requested sound nor
    /// ``fallbackSoundID``, so playback falls through to the synthetic tone.
    ///
    /// Kept apart from ``missingSoundErrorID`` because the two mean opposite
    /// things to whoever greps them: the first is a degraded install of a
    /// correct build, the second is a build assembled without its own default
    /// sound — every alarm in it beeps instead of ringing. `.fault`, not
    /// `.error`, for the same reason.
    static var missingFallbackSoundErrorID: String { "AUDIO-765-DEFAULT-SOUND-MISSING" }

    /// Locate the bundled alarm sound (caf/m4a/wav/mp3 — in that order, with a
    /// ``fallbackSoundID`` fallback) and try to wrap it in `AVAudioPlayer`. If
    /// the bundle hit fails or AVAudioPlayer rejects the file we fall back to
    /// the in-memory synthetic tone so the user still hears *something*.
    ///
    /// Both failing lookups log (#765). Neither changes what is returned — the
    /// synthetic tone stays the last resort. What changes is that "the alarm
    /// beeped instead of ringing" now has something to grep: before this, a
    /// missing sound file, a build with no default sound, and a perfectly
    /// resolved lookup were equally silent, and only the `AVAudioPlayer.init`
    /// failure — the *less* likely cause — left a trace.
    ///
    /// `resourceURL` exists so a test can state which files the bundle holds.
    /// `Bundle.main` in the test host IS the app bundle, so the
    /// no-fallback-either branch is otherwise unreachable from a test: the app
    /// ships `default_alarm.caf`, which is exactly the condition that branch
    /// reports the absence of.
    ///
    /// ⚠️ Reached from `startAlarmSoundLocked`, i.e. inside `queue.sync`, so
    /// unlike every other `AppLogger.emit` call site this one is not
    /// main-thread. `sync` orders it against the calling thread rather than
    /// running it concurrently, which is what `emit`'s unguarded test sink
    /// needs; a test that wants to observe these lines should call this method
    /// directly, as `AudioServiceTests` does, instead of installing a sink and
    /// driving `startAlarmSound` from another thread.
    func resolveAlarmPlayer(
        soundID: String,
        resourceURL: (String, String) -> URL? = { name, ext in
            Bundle.main.url(forResource: name, withExtension: ext)
        }
    ) -> AVAudioPlayer? {
        let url = Self.firstBundledURL(for: soundID, resourceURL: resourceURL)
            ?? fallbackAlarmSoundURL(after: soundID, resourceURL: resourceURL)

        guard let soundURL = url else { return Self.generateAlarmTone() }
        do {
            return try AVAudioPlayer(contentsOf: soundURL)
        } catch {
            let name = soundURL.lastPathComponent
            let desc = error.localizedDescription
            AppLogger.audio.error(
                "AVAudioPlayer init failed for \(name, privacy: .public): \(desc, privacy: .public)"
            )
            return Self.generateAlarmTone()
        }
    }

    /// Look up ``fallbackSoundID`` after `soundID` produced nothing, and report
    /// which of the two failing states we are in.
    ///
    /// Through `AppLogger.emit` rather than `AppLogger.audio.error`: `os.Logger`
    /// hands the caller nothing back, so a branch whose only evidence is its own
    /// log line would be one deletion away from the silence it replaces, with
    /// the suite still green (#731).
    private func fallbackAlarmSoundURL(
        after soundID: String,
        resourceURL: (String, String) -> URL?
    ) -> URL? {
        let tried = Self.alarmSoundExtensions.joined(separator: ",")
        let fallback = Self.firstBundledURL(for: Self.fallbackSoundID, resourceURL: resourceURL)

        // soundID is a preset identifier ("classic", "radar") chosen from a
        // fixed list, never user-entered text — safe to make public, which is
        // what `emit` does to everything it is handed.
        guard let fallback else {
            AppLogger.emit(
                .audio, .fault,
                """
                [\(Self.missingFallbackSoundErrorID)] resolveAlarmPlayer: bundle has neither \
                '\(soundID)' nor '\(Self.fallbackSoundID)' (tried \(tried)); the alarm rings the \
                synthetic tone instead of any real sound
                """
            )
            return nil
        }

        AppLogger.emit(
            .audio, .error,
            """
            [\(Self.missingSoundErrorID)] resolveAlarmPlayer: no bundled file for soundID \
            '\(soundID)' (tried \(tried)); the alarm will ring \(fallback.lastPathComponent) \
            instead of the chosen sound
            """
        )
        return fallback
    }

    /// First hit for `name` across ``alarmSoundExtensions``, in order.
    ///
    /// A plain loop rather than `lazy.compactMap { … }.first`: the lazy
    /// sequence would store `resourceURL`, and a non-escaping parameter cannot
    /// be captured that way — the terse version does not compile.
    private static func firstBundledURL(
        for name: String,
        resourceURL: (String, String) -> URL?
    ) -> URL? {
        for ext in alarmSoundExtensions {
            if let url = resourceURL(name, ext) { return url }
        }
        return nil
    }

    /// Apply per-alarm volume + optional fade-in. The defensive clamp comes
    /// from `Alarm.clampedVolume` so playback and persistence cannot disagree
    /// about what a NaN/Inf value means (#714) — a corrupt payload still
    /// produces a playable alarm, at the same volume everywhere.
    private func configurePlayerVolume(_ player: AVAudioPlayer, target volume: Float, fadeIn: Bool) {
        player.numberOfLoops = -1
        let clampedVolume = Alarm.clampedVolume(volume)
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
        queue.sync {
            audioPlayer?.stop()
            audioPlayer = nil
            stopVibration()
            deactivateAudioSession()
            _currentAlarmID = nil
            _isPaused = false
            _interrupted = false
            _state = .stopped
        }
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
        queue.sync {
            guard _state == .playing else { return }
            audioPlayer?.pause()
            stopVibration()
            _isPaused = true
        }
    }

    /// Resume playback + vibration after `pauseAlarmSound()`. No-op if no
    /// player exists (state != .playing). Idempotent so the bottom sheet's
    /// dismiss path can call it without checking pause state first.
    ///
    /// Does NOT touch `_interrupted`: a top-up resume must not cancel an
    /// in-flight system-interruption recovery (#395). Clearing `_interrupted`
    /// is owned exclusively by the `.ended` branch of `handleAudioInterruption`.
    func resumeAlarmSound() {
        queue.sync {
            guard _state == .playing, audioPlayer != nil else { return }
            resumePlaybackLocked()
        }
    }

    /// Resume the paused looped player + vibration. Must only be called from
    /// `queue` with `audioPlayer != nil`. Clears `_isPaused`. Shared by
    /// `resumeAlarmSound()` (#141), the stacking-replace un-pause (#116/#374)
    /// and interruption recovery (#374/#395).
    ///
    /// Re-activates the audio session before `play()`. A top-up pause that
    /// overlaps a system interruption (#395) leaves the session *deactivated*
    /// by iOS — calling `play()` against a dead session yields silence with no
    /// error, a failed wake. So every resume path reclaims the session first,
    /// falling back to `.silentBecauseConfigFailed` if another app holds it.
    private func resumePlaybackLocked() {
        guard let player = audioPlayer else { return }
        do {
            try configureAudioSession()
        } catch {
            // Session could not be reclaimed (another app owns it). Surface the
            // explicit fallback so the firing UI warns the user instead of
            // showing a "ringing" screen with no sound.
            AppLogger.audio.error(
                "resumePlaybackLocked: session reactivate failed: \(error.localizedDescription, privacy: .public)"
            )
            _isPaused = false
            _state = .silentBecauseConfigFailed
            // On a resume the firing screen that normally renders the
            // `.silentBecauseConfigFailed` banner is often NOT on screen
            // (locked-screen wake, AlarmKit/notification path, or a top-up sheet
            // on top), so the failure had only a Console-log trace — a silent
            // failed wake (#405). Vibration uses AudioToolbox, which works
            // without an audio session, so keep buzzing; and post a process
            // notification that `AppDelegate` turns into a time-sensitive local
            // banner the user actually sees on the lock screen.
            startVibration()
            NotificationCenter.default.post(
                name: Self.resumeAudioFailedNotification,
                object: self
            )
            return
        }
        // `play()` returns false only if the queue refuses — which on a paused
        // looping player should not happen once the session is active again.
        // If it does, leaving `_state == .playing` shows a "ringing" firing
        // screen that only vibrates: silent, banner hidden, no surfaced failure.
        // Mirror `startAlarmSoundLocked`'s play()==false branch and fall to
        // `.vibrationOnly` so the UI reflects the real state (#406).
        if !player.play() {
            AppLogger.audio.error("resumePlaybackLocked: AVAudioPlayer.play() returned false")
            _isPaused = false
            _state = .vibrationOnly
            startVibration()
            return
        }
        startVibration()
        _isPaused = false
    }

    // MARK: - Interruptions

    /// React to an `AVAudioSession` interruption (incoming call, Siri, another
    /// app grabbing audio). On `.began` iOS has already paused our player, so we
    /// mirror that into our own state and stop the vibration timer (otherwise it
    /// keeps buzzing with no sound). On `.ended` we re-activate the session and
    /// resume — an alarm that stays silent after a call is a failed wake (#374).
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        queue.sync {
            switch type {
            case .began:
                // Only act on an active, not-already-paused alarm. If a top-up
                // pause is already in effect we leave it to `resumeAlarmSound()`.
                guard _state == .playing, !_isPaused else { return }
                audioPlayer?.pause()
                stopVibration()
                _isPaused = true
                _interrupted = true
            case .ended:
                guard _interrupted else { return }
                _interrupted = false
                // `resumePlaybackLocked` reactivates the session the system
                // tore down during the interruption before `play()` (#395).
                guard _state == .playing, audioPlayer != nil else { return }
                resumePlaybackLocked()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Vibration

    /// Start a repeating vibration pattern (vibrate every ~1 second).
    /// Must only be called from `queue`.
    private func startVibration() {
        stopVibration()

        // Trigger first vibration immediately
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        // Repeat vibration on a timer attached EXPLICITLY to the main run loop.
        // `Timer.scheduledTimer` attaches to the *caller's* run loop — alarm
        // starts can arrive on a UN-delegate background thread whose run loop
        // stops spinning once the thread is recycled, silently killing the
        // vibration after one tick (#202). `CFRunLoop` is thread-safe, so
        // adding to `RunLoop.main` from the serial queue is allowed.
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        RunLoop.main.add(timer, forMode: .common)
        vibrationTimer = timer
    }

    /// Stop the vibration timer. Must only be called from `queue`.
    private func stopVibration() {
        guard let timer = vibrationTimer else { return }
        vibrationTimer = nil
        // NSTimer should be invalidated on the thread that owns its run loop
        // (main, see `startVibration`). Hop if the call arrived elsewhere.
        if Thread.isMainThread {
            timer.invalidate()
        } else {
            DispatchQueue.main.async { timer.invalidate() }
        }
    }

    // MARK: - Tone Generation
    //
    // The synthetic-tone generator + WAV packer + binary helpers live in
    // `AudioService+Tone.swift` (#182) so this file stays under SwiftLint's
    // `file_length` cap. `resolveAlarmPlayer` calls
    // `Self.generateAlarmTone()` exactly as before — only the physical
    // location moved.
}
