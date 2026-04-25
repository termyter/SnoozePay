import AVFoundation
import AudioToolbox

/// Manages continuous alarm sound playback and vibration.
/// Configures AVAudioSession for playback even when screen is locked,
/// loops the alarm sound until explicitly stopped, and provides
/// a repeating vibration pattern via AudioToolbox.
final class AudioService {

    static let shared = AudioService()

    private var audioPlayer: AVAudioPlayer?
    private var vibrationTimer: Timer?
    private(set) var isPlaying = false

    private init() {}

    // MARK: - Audio Session

    /// Configure the audio session for alarm playback.
    /// Uses `.playback` category so audio continues when screen is locked.
    /// - Returns: `true` if the session is active and ready, `false` otherwise.
    private func configureAudioSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true, options: [])
            return true
        } catch {
            print("[AudioService] Failed to configure audio session: \(error)")
            return false
        }
    }

    /// Deactivate the audio session when alarm is stopped.
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - Alarm Sound

    /// Start playing alarm sound in a loop.
    /// - Parameter soundID: Name of the sound file (without extension) in the app bundle.
    ///   Falls back to a system-generated tone if file is not found.
    func startAlarmSound(soundID: String) {
        guard !isPlaying else { return }

        guard configureAudioSession() else {
            // Audio session unavailable (e.g. another app holds it).
            // Surface explicitly via isPlaying = false so the UI / caller can react.
            // Skip vibration too — without an active session we cannot guarantee playback.
            print("[AudioService] startAlarmSound aborted: audio session unavailable")
            isPlaying = false
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
        // is missing or corrupt (AVAudioPlayer init returns nil).
        var player: AVAudioPlayer?
        if let soundURL = url {
            player = try? AVAudioPlayer(contentsOf: soundURL)
            if player == nil {
                let name = soundURL.lastPathComponent
                print("[AudioService] AVAudioPlayer init failed for \(name), using synthetic tone")
            }
        }
        if player == nil {
            player = Self.generateAlarmTone()
        }

        if let player {
            audioPlayer = player
            player.numberOfLoops = -1
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            isPlaying = true
            startVibration()
        } else {
            // Neither bundled file nor synthetic tone available — refuse to claim playback.
            // We still vibrate, but isPlaying stays false to signal silent failure.
            print("[AudioService] startAlarmSound: no audio source available, vibration only")
            isPlaying = false
            startVibration()
        }
    }

    /// Stop alarm sound and vibration immediately.
    func stopAlarmSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopVibration()
        deactivateAudioSession()
        isPlaying = false
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

        for i in 0..<totalSamples {
            let t = Double(i) / sampleRate
            // Dual-tone: 880 Hz + 660 Hz for recognizable alarm character
            let wave = sin(2.0 * .pi * frequency * t) + 0.6 * sin(2.0 * .pi * 660.0 * t)
            // Amplitude envelope: short fade-in/out to avoid click
            let envelope: Double
            let fadeFrames = Int(sampleRate * 0.02)
            if i < fadeFrames {
                envelope = Double(i) / Double(fadeFrames)
            } else if i > totalSamples - fadeFrames {
                envelope = Double(totalSamples - i) / Double(fadeFrames)
            } else {
                // Pulse pattern: 0.3s on, 0.2s off
                let cyclePos = t.truncatingRemainder(dividingBy: 0.5)
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
