import AVFoundation
import Foundation

// MARK: - Synthetic alarm tone generation
//
// Extracted from `AudioService.swift` (#182) so the host file stays under
// SwiftLint's `file_length` cap. The tone generator is the in-memory
// fallback played when the bundled alarm file is missing or AVAudioPlayer
// rejects it. Behaviour is verbatim — only the physical location moved.

extension AudioService {

    /// Generate a 440 Hz sine wave alarm tone as in-memory WAV data.
    /// Returns an AVAudioPlayer ready to loop, or nil on failure.
    static func generateAlarmTone() -> AVAudioPlayer? {
        let sampleRate: Double = 44100
        let duration: Double = 1.5 // seconds per loop cycle
        let frequency: Double = 880 // A5 — prominent alarm frequency
        let totalSamples = Int(sampleRate * duration)

        let samples = renderToneSamples(
            totalSamples: totalSamples,
            sampleRate: sampleRate,
            frequency: frequency
        )

        let wavData = packWAV(samples: samples, totalSamples: totalSamples)
        return try? AVAudioPlayer(data: wavData)
    }

    /// Build interleaved 16-bit PCM samples with the dual-tone amplitude
    /// envelope (880 Hz + 660 Hz, short fade-in/out, 0.3s-on/0.2s-off pulse).
    private static func renderToneSamples(
        totalSamples: Int,
        sampleRate: Double,
        frequency: Double
    ) -> [Int16] {
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
        return samples
    }

    /// Wrap the rendered PCM samples in a minimal RIFF/WAVE container so
    /// `AVAudioPlayer(data:)` accepts the in-memory blob.
    private static func packWAV(samples: [Int16], totalSamples: Int) -> Data {
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
        return wavData
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
