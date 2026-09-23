import AVFoundation
import XCTest
@testable import SnoozePay

/// Pins the synthetic tone's envelope by its samples (#792).
///
/// The samples are read back from the player `generateAlarmTone()` returns,
/// so the test sees the shipped duration and sample rate and needs no wider
/// access to `renderToneSamples`. The pulse (0.3 s on, 0.2 s off) and the
/// 20 ms edge ramp are this test's own copy of the spec.
///
/// Its own file rather than another case in `AudioServiceTests`, which is
/// already past 900 lines.
final class AudioServiceToneEnvelopeTests: XCTestCase {

    private static let fullScale = Double(Int16.max)
    private static let fadeSeconds = 0.02

    private struct Tone {
        let sampleRate: Double
        let samples: [Int16]

        func peak(from start: Int, to end: Int) -> Double {
            let peak = samples[start..<end].map { abs(Int($0)) }.max() ?? 0
            return Double(peak) / AudioServiceToneEnvelopeTests.fullScale
        }

        func isPulseOff(at index: Int) -> Bool {
            (Double(index) / sampleRate).truncatingRemainder(dividingBy: 0.5) >= 0.3
        }
    }

    /// Decodes the fixed 44-byte header `packWAV` writes, then the 16-bit
    /// little-endian PCM behind it.
    private func renderedTone() throws -> Tone {
        let player = try XCTUnwrap(AudioService.generateAlarmTone())
        let bytes = try [UInt8](XCTUnwrap(player.data, "a player built from data must expose it"))
        XCTAssertEqual(Array(bytes[36..<40]), Array("data".utf8), "the PCM must start right after a 44-byte header")

        let sampleRate = (24..<28).reversed().reduce(0) { $0 << 8 | Int(bytes[$1]) }
        let samples = stride(from: 44, to: bytes.count - 1, by: 2).map {
            Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)
        }
        return Tone(sampleRate: Double(sampleRate), samples: samples)
    }

    /// The closing ramp used to replace the pulse and bring the tone back to
    /// full scale in the last 20 ms, which at 1.5 s is an off phase. Looped,
    /// that burst sat on the seam every cycle.
    func testClosingRamp_keepsAnOffPhaseTailSilent() throws {
        let tone = try renderedTone()
        let count = tone.samples.count
        let tailStart = count - Int(tone.sampleRate * Self.fadeSeconds)

        XCTAssertTrue(
            tone.isPulseOff(at: tailStart) && tone.isPulseOff(at: count - 1),
            "the buffer length changed and its last 20 ms are no longer in an off phase; re-pick the window"
        )
        XCTAssertLessThan(
            tone.peak(from: tailStart, to: count), 0.01,
            "the last 20 ms sit in a pulse off phase and must stay silent, not burst before the loop seam"
        )
        XCTAssertLessThan(
            abs(Double(tone.samples[count - 1])) / Self.fullScale, 0.01,
            "the last sample meets the next cycle's first sample at the loop seam"
        )

        // Without this, an all-zero render would pass every check above.
        let onStart = Int(tone.sampleRate * 0.05)
        let onEnd = Int(tone.sampleRate * 0.25)
        XCTAssertGreaterThan(
            tone.peak(from: onStart, to: onEnd), 0.5,
            "the first on phase must be audible, or the silence asserted above means nothing"
        )
    }

    /// The opening ramp is what keeps the head of the buffer from clicking.
    /// Over the first 2 ms it allows at most 10% of the 1.096 peak (~0.11 of
    /// full scale); an unramped start reaches full scale there.
    func testOpeningRamp_startsFromSilence() throws {
        let tone = try renderedTone()
        let twoMs = Int(tone.sampleRate * 0.002)

        XCTAssertEqual(tone.samples.first, 0, "the loop seam lands on the first sample")
        XCTAssertLessThan(
            tone.peak(from: 0, to: twoMs), 0.15,
            "the first 2 ms must still be on the 20 ms opening ramp, not at full pulse level"
        )
    }
}
