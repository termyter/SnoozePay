import UIKit
import XCTest
@testable import SnoozePay

final class SoundPickerPreviewRenderingTests: XCTestCase {

    func testPlayPauseAndStoppedGlyphsRenderInBothThemes() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let (picker, window) = makePicker(style: style)
            defer { tearDown(picker, window: window) }
            let button = try previewButton(in: picker.view)
            XCTAssertEqual(button.bounds.size, CGSize(width: 48, height: 48))
            XCTAssertTrue(button.accessibilityTraits.contains(.button))
            let play = try visibleGlyph(of: button)

            button.sendActions(for: .touchUpInside)
            let pause = try visibleGlyph(of: button)
            XCTAssertGreaterThan(changedPixels(play, pause), 30, "Playback must visibly change play to pause")

            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(try visibleGlyph(of: button), play, "Stopping must restore the visible play glyph")
        }
    }

    func testPlayingGlyphAndGradientFollowThemeChanges() throws {
        let (picker, window) = makePicker(style: .dark)
        defer { tearDown(picker, window: window) }
        let button = try previewButton(in: picker.view)
        button.sendActions(for: .touchUpInside)

        for style in [UIUserInterfaceStyle.dark, .light, .dark] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            XCTAssertEqual(button.traitCollection.userInterfaceStyle, style, "The host must propagate its theme")
            _ = try visibleGlyph(of: button)
            let background = try XCTUnwrap(button.superview)
            let gradient = try XCTUnwrap(background.layer as? CAGradientLayer)
            let colors = try XCTUnwrap(gradient.colors as? [CGColor])
            XCTAssertEqual(colors, SPSupport.moneyGradientColors(for: button.traitCollection))
            XCTAssertEqual(
                button.tintColor.resolvedColor(with: button.traitCollection),
                AppColors.fgOnMoney.resolvedColor(with: button.traitCollection)
            )
        }
    }

    func testRefusedPlaybackKeepsTheVisiblePlayGlyph() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let (picker, window) = makePicker(style: style, startsPlayback: false)
            defer { tearDown(picker, window: window) }
            let button = try previewButton(in: picker.view)
            let play = try visibleGlyph(of: button)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(try visibleGlyph(of: button), play)
        }
    }

    private func makePicker(
        style: UIUserInterfaceStyle,
        startsPlayback: Bool = true
    ) -> (SoundPickerViewController, UIWindow) {
        let sound = SoundCatalogue.entries[0]
        let picker = SoundPickerViewController(
            sounds: [sound], selectedID: sound.id,
            onSelect: { _ in }, previewSound: { _ in startsPlayback }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = picker
        window.isHidden = false
        window.layoutIfNeeded()
        picker.view.layoutIfNeeded()
        return (picker, window)
    }

    private func tearDown(_ picker: SoundPickerViewController, window: UIWindow) {
        // Stop the display link before releasing its strong target.
        picker.viewWillDisappear(false)
        window.isHidden = true
        window.rootViewController = nil
    }

    private func previewButton(in view: UIView) throws -> UIButton {
        try XCTUnwrap(descendants(of: view).first(where: {
            $0.accessibilityIdentifier == "sound_picker.preview"
        }) as? UIButton, "Missing preview button")
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    // Compare actual pixels with the same frame's glyph hidden: an assigned
    // UIImage alone does not prove that an opaque gradient hasn't covered it.
    private func visibleGlyph(of button: UIButton) throws -> [UInt8] {
        button.layoutIfNeeded()
        let imageView = try XCTUnwrap(button.imageView)
        XCTAssertFalse(imageView.isHidden)
        let background = try XCTUnwrap(button.superview)
        let visible = try pixels(of: background)
        imageView.isHidden = true
        defer { imageView.isHidden = false }
        let hidden = try pixels(of: background)
        XCTAssertGreaterThan(
            changedPixels(visible, hidden), 40,
            "The 18pt glyph must paint contrasting pixels above the gradient"
        )
        return visible
    }

    private func pixels(of view: UIView) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image {
            view.layer.render(in: $0.cgContext)
        }
        let bitmap = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(bitmap, in: CGRect(
                x: 0, y: 0, width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)
            ))
        }
        return bytes
    }

    private func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else {
            XCTFail("Rendering changed bitmap dimensions")
            return 0
        }
        return stride(from: 0, to: lhs.count, by: 4).filter { offset in
            (0..<3).contains { abs(Int(lhs[offset + $0]) - Int(rhs[offset + $0])) > 32 }
        }.count
    }
}
