import AVFoundation
import XCTest
@testable import SnoozePay

final class AudioServiceWAVSampleRateTests: XCTestCase {
    func testContainerUsesSuppliedRateAndPreservesKnownPCM() {
        let samples: [Int16] = [.min, -1, 0, 1, .max]
        let payload: [UInt8] = [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0x01, 0x00, 0xFF, 0x7F]

        let rates: [UInt32] = [8000, 22050, 48000, 96000]
        for rate in rates {
            let bytes = Array(AudioService.packWAV(
                samples: samples, totalSamples: samples.count, sampleRate: rate
            ))
            XCTAssertEqual(bytes.count, 44 + payload.count)
            guard bytes.count >= 44 else { continue }
            XCTAssertEqual(Array(bytes[0..<4]), Array("RIFF".utf8))
            XCTAssertEqual(readUInt32(bytes, at: 4), 36 + UInt32(payload.count))
            XCTAssertEqual(Array(bytes[8..<16]), Array("WAVEfmt ".utf8))
            XCTAssertEqual(readUInt32(bytes, at: 16), 16)
            XCTAssertEqual(Array(bytes[20..<24]), [1, 0, 1, 0], "16-bit PCM is mono")
            XCTAssertEqual(readUInt32(bytes, at: 24), rate)
            XCTAssertEqual(readUInt32(bytes, at: 28), rate * 2)
            XCTAssertEqual(Array(bytes[32..<36]), [2, 0, 16, 0])
            XCTAssertEqual(Array(bytes[36..<40]), Array("data".utf8))
            XCTAssertEqual(readUInt32(bytes, at: 40), UInt32(payload.count))
            XCTAssertEqual(Array(bytes.dropFirst(44)), payload)
        }
    }

    func testGeneratedFallbackRetainsIts44100HzMonoDuration() throws {
        let player = try XCTUnwrap(AudioService.generateAlarmTone())
        let bytes = Array(try XCTUnwrap(player.data))
        XCTAssertEqual(bytes.count, 44 + 132300, "66150 mono 16-bit samples")
        guard bytes.count >= 44 else { return }
        XCTAssertEqual(readUInt32(bytes, at: 4), 36 + 132300)
        XCTAssertEqual(readUInt32(bytes, at: 24), 44100)
        XCTAssertEqual(readUInt32(bytes, at: 28), 88200)
        XCTAssertEqual(readUInt32(bytes, at: 40), 132300)
        XCTAssertEqual(Array(bytes[20..<24]), [1, 0, 1, 0])
        XCTAssertEqual(Array(bytes[32..<36]), [2, 0, 16, 0])
        XCTAssertEqual(player.duration, 1.5, accuracy: 0.001)
    }

    private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { result, index in
            result | UInt32(bytes[offset + index]) << (index * 8)
        }
    }
}
