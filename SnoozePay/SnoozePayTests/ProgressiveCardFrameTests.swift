import UIKit
import XCTest
@testable import SnoozePay

/// The «Прогрессивный режим» card's frame, armed and disarmed (#675).
///
/// Reported by the PM as "the border bug shows up only when the control is
/// off". Armed, the card carries a full 1pt pain border and reads as a framed
/// object. Disarmed it used to drop to `1 / displayScale` — a single physical
/// pixel of an 8% ink — and on the light page that is not an edge: `bg1` on
/// `bg0` is 1.06:1, so the border IS the card, and without it the card sits
/// next to the identically-white «Цена откладывания» card above with nothing
/// to separate them.
///
/// Measured on a light 3× screenshot, the left rail one row of pixels wide:
///
///     before   x=60 (235,236,237), x=61 white          1 px of frame
///     after    x=60…62 (235,236,237), x=63 white       3 px = 1 pt
///
/// Only the *colour* should carry whether the mode is armed. The silhouette
/// must not come and go with it.
@MainActor
final class ProgressiveCardFrameTests: XCTestCase {

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    func testTheFrameHasTheSameWeightArmedAndDisarmed() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let armed = try XCTUnwrap(surface(isOn: true, style: style))
            let disarmed = try XCTUnwrap(surface(isOn: false, style: style))
            XCTAssertEqual(
                disarmed.layer.borderWidth,
                armed.layer.borderWidth,
                accuracy: 0.001,
                """
                the card's frame weight changed with the armed state in \
                \(style == .dark ? "dark" : "light") — armed \
                \(armed.layer.borderWidth)pt vs disarmed \
                \(disarmed.layer.borderWidth)pt. Arming is a colour change, \
                not a silhouette change
                """
            )
        }
    }

    /// A hairline is what the disarmed card had, and what made it disappear.
    /// Pinning "at least a whole point" rather than "== 1" leaves room for the
    /// canon weight to be revisited without this test dictating the number.
    func testTheDisarmedFrameIsAWholePointNotAHairline() throws {
        let disarmed = try XCTUnwrap(surface(isOn: false, style: .light))
        let scale = disarmed.traitCollection.displayScale > 0
            ? disarmed.traitCollection.displayScale
            : 1
        XCTAssertGreaterThanOrEqual(
            disarmed.layer.borderWidth,
            1,
            """
            the disarmed frame is \(disarmed.layer.borderWidth)pt, i.e. back to \
            a \(1 / scale)pt hairline of an 8% ink on a 1.06:1 surface — that is \
            the state the PM reported as having no border at all
            """
        )
    }

    /// The half that must still differ: arming repaints the frame with the
    /// pain tint from `SPMore2.jsx`, disarmed keeps the neutral `stroke1`.
    func testArmingStillChangesTheFrameColour() throws {
        let armed = try XCTUnwrap(surface(isOn: true, style: .light))
        let disarmed = try XCTUnwrap(surface(isOn: false, style: .light))
        XCTAssertNotEqual(
            armed.layer.borderColor.map { UIColor(cgColor: $0) },
            disarmed.layer.borderColor.map { UIColor(cgColor: $0) },
            "arming must still be visible — it is the colour that carries it"
        )
    }

    // MARK: - Fixtures

    /// The card surface as the cell actually builds it, hosted in a window so
    /// the decoration resolves against a real trait collection.
    private func surface(isOn: Bool, style: UIUserInterfaceStyle) -> ProgressiveCardSurface? {
        let cell = ProgressiveScaleCell(style: .default, reuseIdentifier: nil)
        cell.configure(isOn: isOn, chain: [50, 100, 200, 400], accessibilityChain: "")

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 343, height: 400))
        window.overrideUserInterfaceStyle = style
        window.isHidden = false
        hostWindows.append(window)

        cell.frame = CGRect(x: 0, y: 0, width: 343, height: 200)
        window.addSubview(cell)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return descendant(ProgressiveCardSurface.self, in: cell)
    }

    private func descendant<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        for subview in root.subviews {
            if let match = subview as? T { return match }
            if let match = descendant(type, in: subview) { return match }
        }
        return nil
    }
}
