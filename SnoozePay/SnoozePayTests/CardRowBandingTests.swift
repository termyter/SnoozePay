import UIKit
import XCTest
@testable import SnoozePay

/// Light-theme banding on `.insetGrouped` card sections (#515).
///
/// The reported symptom was a striped card: the first and last row of every
/// section filled `#F0F1F2` while the middle rows stayed `#FFFFFF`, and dark
/// was uniform. The lead pointed at `.secondarySystemBackground` in the cells,
/// but that colour is `#F2F2F7` and `styleAsCardRow` overwrites the cell's own
/// `backgroundColor` with `.clear` in `willDisplay` anyway.
///
/// The actual source is the ambient stop of `--sp-shadow-1`. Only section caps
/// carry it (`CardRowBackgroundView` skips it for `.middle`), it is a
/// clear-filled `CAShapeLayer` sublayer, and Core Animation draws a layer's
/// shadow *above* whatever is already composited behind it — so the blurred
/// silhouette's solid interior landed on the card fill rather than only
/// haloing around it. Dark drops the ambient layer entirely, which is why the
/// stripes were light-only.
@MainActor
final class CardRowBandingTests: XCTestCase {

    /// Rows only resolve their theme through a real hierarchy, so every
    /// subject is hosted in a window that outlives the assertion.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - The decoration must not paint over the surface it decorates

    func testAmbientStop_isMaskedOutOfTheCardSurface() throws {
        let row = laidOutRow(position: .first, style: .light)
        let ambient = try XCTUnwrap(
            ambientLayer(of: row),
            "a light section cap should carry the ambient shadow-1 stop"
        )
        let mask = try XCTUnwrap(
            ambient.mask as? CAShapeLayer,
            "an unmasked ambient stop washes the card it is supposed to lift"
        )
        let path = try XCTUnwrap(mask.path)
        let spread = AppShadow.ambientShadow1Spread

        let insideTheCard = CGPoint(x: spread + row.bounds.midX, y: spread + row.bounds.midY)
        XCTAssertFalse(
            path.contains(insideTheCard, using: .evenOdd),
            "the ambient stop must not composite over the row's own fill"
        )

        let belowTheCard = CGPoint(x: spread + row.bounds.midX, y: spread + row.bounds.maxY + 2)
        XCTAssertTrue(
            path.contains(belowTheCard, using: .evenOdd),
            "…but the halo around the card is the whole point of the stop"
        )
    }

    /// The asymmetry that turned a wash into visible stripes: caps carry the
    /// ambient stop, middles never do.
    func testMiddleRows_carryNoAmbientStop() {
        XCTAssertNil(ambientLayer(of: laidOutRow(position: .middle, style: .light)))
    }

    func testDarkRows_carryNoAmbientStop() {
        for position in [CardRowPosition.first, .middle, .last, .single] {
            XCTAssertNil(
                ambientLayer(of: laidOutRow(position: position, style: .dark)),
                "\(position) in dark must stay on the single deep stop"
            )
        }
    }

    // MARK: - Measured fill

    /// The assertion the issue actually asks for: a cap row and a middle row of
    /// the same section must render the same fill, in both themes.
    func testCapRowAndMiddleRow_renderTheSameFill_inBothThemes() throws {
        try XCTSkipUnless(
            rendererReproducesShadows(),
            "`CALayer.render(in:)` does not composite shadows here — this "
            + "measurement cannot see the defect, so it must not claim to"
        )
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cap = renderedFill(position: .first, style: style)
            let middle = renderedFill(position: .middle, style: style)
            assertSameColour(cap, middle, "cap vs middle row fill in \(style.debugName)")
            assertSameColour(
                cap, AppColors.bg1.resolved(style),
                "cap row fill vs the bg1 token in \(style.debugName)"
            )
        }
    }

    /// Why the issue title says `#F0F1F2` and not `#F2F2F7`: the reported
    /// colour is `bg1` under the ambient stop, not the system grey the lead
    /// blamed. If this ever stops matching, the shadow recipe moved and the
    /// diagnosis above needs rereading.
    func testTheReportedColour_isTheAmbientWashOverBg1_notTheSystemGrey() {
        let wash = UIColor(red: 8.0 / 255.0, green: 14.0 / 255.0, blue: 30.0 / 255.0, alpha: 0.06)
        let washed = channels(composite(wash, over: AppColors.bg1.resolved(.light)))
        XCTAssertEqual(washed.red * 255, 240, accuracy: 0.6, "0xF0")
        XCTAssertEqual(washed.green * 255, 241, accuracy: 0.6, "0xF1")
        XCTAssertEqual(washed.blue * 255, 242, accuracy: 0.6, "0xF2")

        let systemGrey = channels(UIColor.secondarySystemBackground.resolved(.light))
        XCTAssertNotEqual(systemGrey.red * 255, 240, accuracy: 0.6, "#F2F2F7 is a different colour")
    }

    // MARK: - Fixtures

    private func laidOutRow(
        position: CardRowPosition,
        style: UIUserInterfaceStyle
    ) -> CardRowBackgroundView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 343, height: 52))
        window.overrideUserInterfaceStyle = style
        window.backgroundColor = AppColors.bg0
        window.isHidden = false
        hostWindows.append(window)

        let row = CardRowBackgroundView(position: position, cornerRadius: AppRadius.sm)
        row.frame = window.bounds
        window.addSubview(row)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return row
    }

    private func ambientLayer(of row: UIView) -> CAShapeLayer? {
        row.layer.sublayers?
            .first { $0.name == AppShadow.ambientShadow1LayerName } as? CAShapeLayer
    }

    /// Composite the row over its page and read the pixel at the row's centre.
    private func renderedFill(
        position: CardRowPosition,
        style: UIUserInterfaceStyle
    ) -> UIColor {
        let row = laidOutRow(position: position, style: style)
        guard let window = row.window else {
            XCTFail("the row lost its host window")
            return .clear
        }
        return pixel(of: window, at: CGPoint(x: window.bounds.midX, y: window.bounds.midY))
    }

    /// A clear-filled shape layer with an opaque shadow over white: if the
    /// renderer sees shadows at all, the centre pixel comes back dark.
    private func rendererReproducesShadows() -> Bool {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        window.backgroundColor = .white
        window.isHidden = false
        hostWindows.append(window)

        let probe = CAShapeLayer()
        probe.frame = window.bounds
        let path = UIBezierPath(rect: window.bounds).cgPath
        probe.path = path
        probe.fillColor = UIColor.clear.cgColor
        probe.shadowPath = path
        probe.shadowColor = UIColor.black.cgColor
        probe.shadowOpacity = 1
        probe.shadowRadius = 0
        probe.shadowOffset = .zero
        window.layer.addSublayer(probe)

        let centre = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        return channels(pixel(of: window, at: centre)).red < 0.5
    }

    // MARK: - Pixels

    private func pixel(of view: UIView, at point: CGPoint) -> UIColor {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let bitmap = image.cgImage else {
            XCTFail("rendering produced no bitmap")
            return .clear
        }
        let scale = image.scale
        let x = min(max(Int(point.x * scale), 0), bitmap.width - 1)
        let y = min(max(Int(point.y * scale), 0), bitmap.height - 1)
        guard let sample = bitmap.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            XCTFail("could not crop the sample pixel")
            return .clear
        }
        return colour(of: sample)
    }

    private func colour(of sample: CGImage) -> UIColor {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        buffer.initialize(repeating: 0, count: 4)
        defer {
            buffer.deinitialize(count: 4)
            buffer.deallocate()
        }
        guard let context = CGContext(
            data: buffer,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("could not build a 1×1 sampling context")
            return .clear
        }
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(
            red: CGFloat(buffer[0]) / 255.0,
            green: CGFloat(buffer[1]) / 255.0,
            blue: CGFloat(buffer[2]) / 255.0,
            alpha: CGFloat(buffer[3]) / 255.0
        )
    }

    /// 3/255 of slack absorbs colour-space round-tripping through the
    /// renderer. The defect this file pins is 15/255 per channel.
    private func assertSameColour(_ lhs: UIColor, _ rhs: UIColor, _ message: String) {
        let left = channels(lhs)
        let right = channels(rhs)
        let detail = "\(message): \(hex(lhs)) vs \(hex(rhs))"
        XCTAssertEqual(left.red * 255, right.red * 255, accuracy: 3, detail)
        XCTAssertEqual(left.green * 255, right.green * 255, accuracy: 3, detail)
        XCTAssertEqual(left.blue * 255, right.blue * 255, accuracy: 3, detail)
    }

    // MARK: - Colour maths

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func channels(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(color)")
            return Channels(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return Channels(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func composite(_ foreground: UIColor, over background: UIColor) -> UIColor {
        let fore = channels(foreground)
        let back = channels(background)
        let alpha = fore.alpha
        return UIColor(
            red: alpha * fore.red + (1 - alpha) * back.red,
            green: alpha * fore.green + (1 - alpha) * back.green,
            blue: alpha * fore.blue + (1 - alpha) * back.blue,
            alpha: 1
        )
    }

    private func hex(_ color: UIColor) -> String {
        let rgb = channels(color)
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.red * 255).rounded()),
            Int((rgb.green * 255).rounded()),
            Int((rgb.blue * 255).rounded())
        )
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIUserInterfaceStyle {
    var debugName: String {
        self == .dark ? "dark" : "light"
    }
}
