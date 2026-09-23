import AVFoundation
import Foundation
import os

// MARK: - Synthetic alarm tone generation
//
// Extracted from `AudioService.swift` (#182) so the host file stays under
// SwiftLint's `file_length` cap. The tone generator is the in-memory
// fallback played when the bundled alarm file is missing or AVAudioPlayer
// rejects it. The #182 move itself was verbatim; the envelope changed in #792.

extension AudioService {

    /// Generate the synthetic alarm tone as in-memory WAV data: a 1.5 s mono
    /// 16-bit PCM buffer at 44.1 kHz carrying two summed sine partials
    /// (880 Hz, plus 660 Hz at 0.6 amplitude), gated by a 0.3s-on/0.2s-off
    /// pulse and multiplied by a 20 ms ramp at each buffer edge.
    ///
    /// The buffer loops (`numberOfLoops = -1`,
    /// `AudioService.configurePlayerVolume`), so its two edges meet at a seam
    /// every 1.5 s. At this length the pulse is already off over 1.3–1.5 s,
    /// so the tail reaches the seam silent. Until #792 the closing ramp
    /// replaced the pulse instead of scaling it, and brought the tone back to
    /// full scale in that off phase right before the seam.
    ///
    /// Returns an AVAudioPlayer over that buffer — looping is the caller's to
    /// set via `numberOfLoops` — or nil if AVAudioPlayer rejects the data,
    /// which is the only way this returns nil.
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
        do {
            return try AVAudioPlayer(data: wavData)
        } catch {
            // Last-resort fallback failed — the alarm fires with vibration
            // only. Log it so "why no tone" is diagnosable from Console
            // instead of requiring a source read (#210).
            let desc = String(describing: error)
            AppLogger.audio.error("generateAlarmTone: AVAudioPlayer init failed: \(desc, privacy: .public)")
            return nil
        }
    }

    /// Build the single-channel 16-bit PCM samples: the caller's carrier
    /// frequency plus a fixed 660 Hz partial at 0.6 amplitude, under a
    /// 0.3s-on/0.2s-off pulse multiplied by a 20 ms linear ramp at each
    /// buffer edge — see the seam described on `generateAlarmTone()`.
    ///
    /// The summed partials peak at 1.566 (880 and 660 are 4:3, so the crests
    /// never coincide), which the 0.7 scale below leaves at 1.096. That means
    /// `Int16(clamping:)` clips 2816 of the 66150 samples — 4.3% — and the
    /// distortion is part of the "recognizable alarm character", not an
    /// accident. Anyone raising 0.6 or 0.7 should know the headroom is
    /// already negative.
    private static func renderToneSamples(
        totalSamples: Int,
        sampleRate: Double,
        frequency: Double
    ) -> [Int16] {
        var samples = [Int16]()
        samples.reserveCapacity(totalSamples)

        for sampleIndex in 0..<totalSamples {
            let timeSeconds = Double(sampleIndex) / sampleRate
            // Dual-tone for a recognizable alarm character; the partials and
            // the headroom they leave are in the docstring above.
            let wave = sin(2.0 * .pi * frequency * timeSeconds)
                + 0.6 * sin(2.0 * .pi * 660.0 * timeSeconds)
            // Pulse pattern: 0.3s on, 0.2s off.
            let cyclePos = timeSeconds.truncatingRemainder(dividingBy: 0.5)
            let pulse = cyclePos < 0.3 ? 1.0 : 0.0
            // Edge ramps scale the pulse, never replace it, so an off phase
            // stays silent at the loop seam (#792). Only the buffer edges are
            // ramped; the pulse's own on/off steps are not.
            let fadeFrames = Double(Int(sampleRate * 0.02))
            let edgeRamp = min(
                1.0,
                Double(sampleIndex) / fadeFrames,
                Double(totalSamples - sampleIndex) / fadeFrames
            )
            let envelope = pulse * edgeRamp
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
