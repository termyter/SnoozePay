import UIKit
import XCTest
@testable import SnoozePay

/// Issue #576 — `SPButton` activates a *required* `heightAnchor` on itself but
/// used to leave `translatesAutoresizingMaskIntoConstraints` at its `true`
/// default, so every one of the 34 call sites had to remember the reset.
///
/// ## Why this measures a NEIGHBOUR and not the button
///
/// Asserting only "a fresh button has the flag off" would be a tautology
/// restating the fix. The defect that cost a day in #467 was never visible on
/// the button: UIKit pinned it to its birth frame `.zero` at required
/// priority, that collided with its own required 56pt height, and Auto Layout
/// paid for the collision out of whatever else was breakable — the intrinsic
/// heights of the SIBLINGS. The log from that day:
///
/// ```
/// confirmDelete.title        = (24.0, 40.0, 330.0, 0.0)   ← width, no height
/// confirmDelete.deleteButton = (0.0, 0.0, 0.0, 0.0)
/// ```
///
/// So the harness below is a card-shaped chain — label on top, button pinned
/// to the bottom, the two tied together — and the assertion the fix has to buy
/// is on the *label's* height.
///
/// ## Why it is red on the old code, whichever constraint the engine breaks
///
/// Leaving the flag on installs required constraints for position AND size.
/// Two resolutions are possible and both fail here:
///
/// 1. The autoresizing height wins → the button lays out 0pt tall, and
///    the button-height assertion fails outright.
/// 2. The button's own `heightAnchor` wins → the autoresizing *position*
///    constraints survive regardless, pinning `button.top` to 0. The chain
///    then demands `label.bottom == -16`, which is unreachable, so the label's
///    intrinsic height (hugging 250 / compression 750) is what gives way and
///    the label measures 0 — exactly the #467 screenshot.
///
/// The call site here deliberately does NOT reset the flag on the button. That
/// omission is the whole point: it is what a forgetful caller writes, and
/// after the fix it must stop mattering.
final class SPButtonAutoresizingContractTests: XCTestCase {

    private let containerWidth: CGFloat = 320
    private let containerHeight: CGFloat = 200
    private let inset: CGFloat = 24
    private let gap: CGFloat = 16

    // MARK: - The regression

    func testSiblingKeepsItsHeightWhenTheCallerForgetsTheFlag() {
        for size in [SPButton.Size.lg, .md, .sm] {
            // `container` is held for the whole check on purpose: a view does
            // not retain its superview, and letting the card die would take
            // the constraints down with it mid-assertion.
            let (container, label, button) = layoutCard(size: size)
            XCTAssertEqual(container.bounds.height, containerHeight, accuracy: 0.5)

            // The load-bearing one: on the old code this collapsed to 0 while
            // keeping its x/y/width, and the screen read as blank.
            XCTAssertGreaterThan(
                label.frame.height, 0,
                "A neighbour of an SPButton lost its height — the button is "
                    + "pinned to its autoresizing frame again (size: \(size))"
            )

            let expectedLabelHeight = containerHeight - inset * 2 - gap - size.height
            XCTAssertEqual(
                label.frame.height, expectedLabelHeight, accuracy: 0.5,
                "The vertical chain no longer resolves to the geometry the "
                    + "card asks for (size: \(size))"
            )

            XCTAssertEqual(
                button.frame.height, size.height, accuracy: 0.5,
                "The button's own required height lost to its autoresizing "
                    + "frame (size: \(size))"
            )
            XCTAssertGreaterThan(
                button.frame.width, 0,
                "The button collapsed horizontally — `.zero` frame again "
                    + "(size: \(size))"
            )
        }
    }

    // MARK: - The contract itself

    func testFreshButtonOwnsItsAutoresizingFlag() {
        for size in [SPButton.Size.lg, .md, .sm] {
            for variant in [SPButton.Variant.money, .pain, .warn, .ghost, .quiet] {
                let button = SPButton(title: "Отложить", variant: variant, size: size)
                XCTAssertFalse(
                    button.translatesAutoresizingMaskIntoConstraints,
                    "SPButton must reset the flag on itself; it activates a "
                        + "required heightAnchor on self and cannot be laid "
                        + "out by frame (\(variant)/\(size))"
                )
            }
        }
    }

    // MARK: - Harness

    /// A minimal stand-in for the `ConfirmDeleteAlarmViewController` card that
    /// exposed this in #467: a text block whose height comes from its content,
    /// and a button welded to the bottom edge underneath it.
    private func layoutCard(size: SPButton.Size) -> (UIView, UILabel, SPButton) {
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        )

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 17)
        label.text = "Удалить будильник?"

        // No `translatesAutoresizingMaskIntoConstraints = false` here — on
        // purpose. See the type doc.
        let button = SPButton(title: "Удалить", variant: .pain, size: size, fullWidth: true)

        container.addSubview(label)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),

            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: gap),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset)
        ])

        container.setNeedsLayout()
        container.layoutIfNeeded()

        return (container, label, button)
    }
}
