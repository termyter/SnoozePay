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
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            print("Failed to configure audio session: \(error)")
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

        configureAudioSession()

        // Try to find the sound file in the bundle
        let url: URL? = Bundle.main.url(forResource: soundID, withExtension: "caf")
            ?? Bundle.main.url(forResource: soundID, withExtension: "m4a")
            ?? Bundle.main.url(forResource: soundID, withExtension: "wav")
            ?? Bundle.main.url(forResource: soundID, withExtension: "mp3")
            ?? Bundle.main.url(forResource: "default_alarm", withExtension: "caf")
            ?? Bundle.main.url(forResource: "default_alarm", withExtension: "m4a")

        guard let soundURL = url else {
            print("Alarm sound file not found for soundID: \(soundID)")
            // Even without sound, start vibration
            startVibration()
            isPlaying = true
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Failed to create audio player: \(error)")
        }

        startVibration()
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
}
