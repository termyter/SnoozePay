import UIKit
import XCTest
@testable import SnoozePay

/// The volume picker's seed — the last live boundary between a persisted
/// `Alarm.volume` and what the screen draws (#766).
///
/// `VolumePickerViewController.init` is the only writer of `volume` that is not
/// already bounded: `sliderChanged()` quantises inside `0...1`, and the model
/// side is clamped on construction and on decode. Until now the picker's own
/// clamp was covered by nothing — `AlarmEditorCopyTests` builds this screen
/// once, with `volume: 0.5`, which no clamp touches. Replacing
/// `Alarm.clampedVolume(volume)` in the initialiser with `volume` left the
/// whole suite green.
///
/// The reading is taken off the rendered label rather than off `slider.value`
/// on purpose: `UISlider` clamps to its own `minimumValue…maximumValue`, so the
/// slider would show `0`/`1` for an out-of-range seed even with no clamp of our
/// own — a green oracle for a broken screen. The percentage label has no such
/// safety net; `Int(_:)` in `applyVolumeToUI` traps outright on a NaN.
///
/// Shaped after `AlarmEditorCopyTests.testSoundPickerClampsACorruptVolumeSeedInsteadOfRenderingIt`,
/// which does the same job for the *other* picker. It lives there rather than
/// here because that file owns the sound screen; this file exists separately
/// because `AlarmEditorCopyTests` is already 998 lines and SwiftLint's
/// `file_length` turns into an error at 1000.
final class VolumePickerSeedTests: XCTestCase {

    /// Expectations are literals, never `Alarm.clampedVolume(seed)` rendered
    /// back: an oracle computed by the code under test agrees with any clamp,
    /// including its absence.
    ///
    /// - `1.4` → «100%»: an over-range seed is pulled down to the ceiling.
    /// - `-0.2` → «0%»: a negative seed is pulled up to the floor, not to full.
    /// - `.nan` → «100%»: corrupt data has to ring loudly. Degrading to `0%`
    ///   would turn a bad byte on disk into an alarm nobody hears, which is the
    ///   one failure this app cannot have.
    func testCorruptVolumeSeedIsClampedBeforeItIsRendered() {
        for (seed, expected) in [(Float(1.4), "100%"), (Float(-0.2), "0%"), (Float.nan, "100%")] {
            let rendered = Self.readings(volume: seed)
            XCTAssertTrue(
                rendered.contains(expected),
                "seed \(seed) should read «\(expected)», the screen reads \(rendered)"
            )
        }
    }

    /// The clamp must not touch healthy data on its way in — an alarm saved at
    /// 40% has to open at 40%. Without this, "clamp everything to 1.0" would
    /// satisfy every assertion above.
    func testInRangeVolumeSeedIsRenderedUnchanged() {
        for (seed, expected) in [(Float(0.4), "40%"), (Float(0), "0%"), (Float(1), "100%")] {
            let rendered = Self.readings(volume: seed)
            XCTAssertTrue(
                rendered.contains(expected),
                "seed \(seed) should read «\(expected)», the screen reads \(rendered)"
            )
        }
    }

    /// Everything the picker renders for the given seed. `volume` is private
    /// and only settable through the initialiser, so each seed needs its own
    /// instance.
    private static func readings(volume: Float) -> [String] {
        let picker = VolumePickerViewController(volume: volume, fadeIn: false)
        picker.loadViewIfNeeded()
        return strings(in: picker.view)
    }

    private static func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }
}
