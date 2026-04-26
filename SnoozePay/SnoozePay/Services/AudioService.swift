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
    func startAlarmSound(soundID: String, alarmID: UUID? = nil) {
        // Already in a non-stopped state — preserve the existing pipeline.
        // Earlier guard was `!isPlaying` (Bool); using state covers
        // `.vibrationOnly` and `.silentBecauseConfigFailed` so we don't try to
        // restart on top of a partial fallback either.
        guard state == .stopped else {
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

        // Try to find the sound file in the bundle
        let url: URL? = Bundle.main.url(forResource: soundID, withExtension: "caf")
            ?? Bundle.main.url(forResource: soundID, withExtension: "m4a")
            ?? Bundle.main.url(forResource: soundID, withExtension: "wav")
            ?? Bundle.main.url(forResource: soundID, withExtension: "mp3")
            ?? Bundle.main.url(forResource: "default_alarm", withExtension: "caf")
            ?? Bundle.main.url(forResource: "default_alarm", withExtension: "m4a")

        // Try the bundled file first; fall back to synthetic tone if the file
        // is missing or AVAudioPlayer rejects it (corrupt / format mismatch).
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
        if player == nil {
            player = Self.generateAlarmTone()
        }

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
        player.numberOfLoops = -1
        player.volume = 1.0

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

    /// Stop alarm sound and vibration immediately.
    func stopAlarmSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopVibration()
        deactivateAudioSession()
        currentAlarmID = nil
        state = .stopped
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

    /// Generate a 440 Hz sine wave alarm tone as in-memory WAV data.
    /// Returns an AVAudioPlayer ready to loop, or nil on failure.
    private static func generateAlarmTone() -> AVAudioPlayer? {
        let sampleRate: Double = 44100
        let duration: Double = 1.5 // seconds per loop cycle
        let frequency: Double = 880 // A5 — prominent alarm frequency
        let totalSamples = Int(sampleRate * duration)

        // Build interleaved 16-bit PCM samples with amplitude envelope
        var samples = [Int16]()
        samples.reserveCapacity(totalSamples)

        for sampleIndex in 0..<totalSamples {
            let timeSeconds = Double(sampleIndex) / sampleRate
            // Dual-tone: 880 Hz + 660 Hz for recognizable alarm character
            let wave = sin(2.0 * .pi * frequency * timeSeconds)
                + 0.6 * sin(2.0 * .pi * 660.0 * timeSeconds)
            // Amplitude envelope: short fade-in/out to avoid click
            let envelope: Double
            let fadeFrames = Int(sampleRate * 0.02)
            if sampleIndex < fadeFrames {
                envelope = Double(sampleIndex) / Double(fadeFrames)
            } else if sampleIndex > totalSamples - fadeFrames {
                envelope = Double(totalSamples - sampleIndex) / Double(fadeFrames)
            } else {
                // Pulse pattern: 0.3s on, 0.2s off
                let cyclePos = timeSeconds.truncatingRemainder(dividingBy: 0.5)
                envelope = cyclePos < 0.3 ? 1.0 : 0.0
            }
            let amplitude = wave * envelope * 0.7
            let sample = Int16(clamping: Int(amplitude * Double(Int16.max)))
            samples.append(sample)
        }

        // Build WAV header + data
        let dataSize = totalSamples * 2 // 16-bit = 2 bytes per sample
        var wavData = Data()
        wavData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wavData.append(contentsOf: UInt32(36 + dataSize).littleEndianBytes)
        wavData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        wavData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        wavData.append(contentsOf: UInt32(16).littleEndianBytes)           // chunk size
        wavData.append(contentsOf: UInt16(1).littleEndianBytes)            // PCM format
        wavData.append(contentsOf: UInt16(1).littleEndianBytes)            // mono
        wavData.append(contentsOf: UInt32(44100).littleEndianBytes)        // sample rate
        wavData.append(contentsOf: UInt32(44100 * 2).littleEndianBytes)    // byte rate
        wavData.append(contentsOf: UInt16(2).littleEndianBytes)            // block align
        wavData.append(contentsOf: UInt16(16).littleEndianBytes)           // bits per sample
        wavData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wavData.append(contentsOf: UInt32(dataSize).littleEndianBytes)

        samples.withUnsafeBytes { rawBuffer in
            wavData.append(contentsOf: rawBuffer)
        }

        return try? AVAudioPlayer(data: wavData)
    }
}

// MARK: - Binary helpers

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        let value = self.littleEndian
        return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }
}

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        let value = self.littleEndian
        return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }
}
