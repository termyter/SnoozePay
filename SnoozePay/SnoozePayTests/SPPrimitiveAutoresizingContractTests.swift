import UIKit
import XCTest
@testable import SnoozePay

/// Issue #584 — the same trap `SPButton` was dug out of in #576 / PR #583,
/// inherited by five more design-system primitives. Each activates a required
/// size constraint **on itself** while leaving
/// `translatesAutoresizingMaskIntoConstraints` at its `true` default, so
/// correctness rested on every call site remembering the reset:
///
/// | primitive | its own constraint |
/// |---|---|
/// | `SPPill` | `heightAnchor == 26` |
/// | `SPRow` | `heightAnchor >= 44` |
/// | `SPAmountPreset` | `heightAnchor >= 88` |
/// | `SPSegmented` | `heightAnchor == 44` |
/// | `SPSnoozePrice` | `heightAnchor >= 80` |
///
/// ## Why this measures a NEIGHBOUR
///
/// Asserting "a fresh primitive has the flag off" alone would restate the fix
/// rather than test it. The damage in #467 was never visible on the offending
/// view: UIKit pins it to its birth frame `.zero` at required priority, that
/// collides with its own required height, and Auto Layout pays for the
/// collision out of whatever else is breakable — the intrinsic heights of the
/// SIBLINGS, which keep their x/y/width and measure 0 tall. So the harness
/// below is a card-shaped chain (label on top, primitive welded to the bottom
/// edge, the two tied together) and the load-bearing assertion is on the
/// *label's* height.
///
/// ## Why it is red on the old code, whichever constraint the engine breaks
///
/// The harness deliberately does NOT reset the flag at the call site — that
/// omission is the whole point. With the flag left on, the chain is
/// unsatisfiable two ways over, and both resolutions fail here:
///
/// 1. The autoresizing `height == 0` wins → the primitive lays out 0pt tall
///    and the minimum-height assertion fails outright.
/// 2. The primitive's own `heightAnchor` wins → the autoresizing *position*
///    constraints survive regardless, pinning `primitive.top` to 0. The chain
///    then demands `label.bottom == -gap`, which is unreachable, so the
///    label's intrinsic height gives way and the label measures 0 — exactly
///    the #467 screenshot.
///
/// Three of the five (`SPRow`, `SPAmountPreset`, `SPSnoozePrice`) use `>=`,
/// where the break is quieter still: an unsatisfiable inequality need not
/// print "Unable to simultaneously satisfy constraints" at all, so a collapsed
/// neighbour is the only signal there ever was. That is precisely why it wants
/// a test rather than a console habit.
final class SPPrimitiveAutoresizingContractTests: XCTestCase {

    /// A primitive under test plus the floor its own constraint promises.
    private struct Subject {
        let name: String
        let minimumHeight: CGFloat
        let make: () -> UIView
    }

    private let containerWidth: CGFloat = 320
    private let containerHeight: CGFloat = 260
    private let inset: CGFloat = 24
    private let gap: CGFloat = 16

    private var subjects: [Subject] {
        [
            Subject(name: "SPPill", minimumHeight: 26) {
                SPPill(text: "Прогрессив", tone: .pain)
            },
            Subject(name: "SPRow", minimumHeight: 44) {
                SPRow(title: "Громкость и нарастание", subtitle: "За 30 секунд", divider: false)
            },
            Subject(name: "SPAmountPreset", minimumHeight: 88) {
                SPAmountPreset(value: 149, label: "Бонус 5%", popular: true)
            },
            Subject(name: "SPSegmented", minimumHeight: 44) {
                SPSegmented(options: [
                    SPSegmented.Option(value: "system", label: "Система"),
                    SPSegmented.Option(value: "light", label: "Светлая"),
                    SPSegmented.Option(value: "dark", label: "Тёмная")
                ])
            },
            Subject(name: "SPSnoozePrice", minimumHeight: 80) {
                SPSnoozePrice(price: 100, minutes: 5, tone: .warn, hint: "Уже 3-я задержка")
            }
        ]
    }

    // MARK: - The regression

    func testSiblingKeepsItsHeightWhenTheCallerForgetsTheFlag() {
        for subject in subjects {
            // `container` is held for the whole check on purpose: a view does
            // not retain its superview, and letting the card die would take
            // the constraints down with it mid-assertion.
            let (container, label, primitive) = layoutCard(subject)
            XCTAssertEqual(container.bounds.height, containerHeight, accuracy: 0.5)

            // The load-bearing one: on the old code this collapsed to 0 while
            // keeping its x/y/width, and the screen read as blank.
            XCTAssertGreaterThan(
                label.frame.height, 0,
                "A neighbour of a \(subject.name) lost its height — the "
                    + "primitive is pinned to its autoresizing frame again"
            )

            XCTAssertGreaterThanOrEqual(
                primitive.frame.height, subject.minimumHeight - 0.5,
                "\(subject.name) laid out \(primitive.frame.height)pt tall, under the "
                    + "\(subject.minimumHeight)pt its own constraint promises — that "
                    + "constraint lost to the autoresizing frame"
            )
            XCTAssertGreaterThan(
                primitive.frame.width, 0,
                "\(subject.name) collapsed horizontally — `.zero` frame again"
            )
        }
    }

    // MARK: - The contract itself

    func testFreshPrimitiveOwnsItsAutoresizingFlag() {
        for subject in subjects {
            let primitive = subject.make()
            XCTAssertFalse(
                primitive.translatesAutoresizingMaskIntoConstraints,
                "\(subject.name) must reset the flag on itself; it activates a "
                    + "required size constraint on self and cannot be laid out by frame"
            )
        }
    }

    // MARK: - Harness

    /// A minimal stand-in for the card that exposed this in #467: a text block
    /// whose height comes from its content, and the primitive welded to the
    /// bottom edge underneath it.
    private func layoutCard(_ subject: Subject) -> (UIView, UILabel, UIView) {
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        )

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 17)
        label.text = "Заголовок карточки"
        // Prefer the intrinsic height so the slack in the chain lands on the
        // primitive, not on the label. Hugging does not affect COMPRESSION, so
        // the label still gives way under the required autoresizing
        // constraints of a broken primitive — it stays a working sensor.
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)

        // No `translatesAutoresizingMaskIntoConstraints = false` here — on
        // purpose. See the type doc.
        let primitive = subject.make()

        container.addSubview(label)
        container.addSubview(primitive)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),

            primitive.topAnchor.constraint(equalTo: label.bottomAnchor, constant: gap),
            // Centred between soft edges rather than pinned to both: the pills
            // hug their content while the rows and tiles stretch, and a
            // required full-width pin would fight the hugging ones.
            primitive.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            primitive.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: inset
            ),
            primitive.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -inset
            ),
            primitive.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset)
        ])

        container.setNeedsLayout()
        container.layoutIfNeeded()

        return (container, label, primitive)
    }
}
