import XCTest
import UserNotifications
@testable import SnoozePay

/// Pins the card composition of the permissions screen after #566 removed the
/// Critical Alerts affordance.
///
/// The screen used to mount three cards, the middle one permanently stuck on
/// "Недоступно": it advertised ringing through silent mode / Do Not Disturb,
/// which AlarmKit — the current scheduling backend — already delivers, and it
/// was gated on an entitlement Apple grants on application and effectively
/// never to alarm apps. Two cards remain.
///
/// Worth a test rather than a screenshot because the composition is built in a
/// literal array inside `setupUI`. Nothing else fails if a kind is dropped,
/// duplicated or reordered — the screen simply renders the wrong promise, and
/// the tap routing in `handleGrantTap` follows the card it was built with.
final class PermissionsScreenCompositionTests: XCTestCase {

    // MARK: - Card composition

    func testScreenMountsExactlyTwoPermissionCards() {
        let cards = mountedCards(of: makeLoadedSUT())

        XCTAssertEqual(
            cards.count, 2,
            "Critical Alerts is gone (#566) — the screen must mount notifications + background only"
        )
    }

    func testCardsReadNotificationsThenBackground_inThatOrder() {
        let titles = mountedCards(of: makeLoadedSUT()).compactMap { title(of: $0) }

        XCTAssertEqual(
            titles,
            [PermissionKind.notifications.title, PermissionKind.sound.title],
            "order is the JSX order minus the removed middle card"
        )
    }

    func testNoCardAdvertisesCriticalAlerts() {
        let copy = mountedCards(of: makeLoadedSUT()).flatMap { labelTexts(in: $0) }

        for text in copy {
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("critical"),
                "leftover Critical Alerts copy on the permissions screen: \(text)"
            )
        }
    }

    // MARK: - Kind metadata

    /// The remaining kinds must keep distinct glyphs and copy — a switch that
    /// lost an arm during the removal would collapse them onto one another.
    func testRemainingKindsStayDistinct() {
        let notifications = PermissionKind.notifications
        let background = PermissionKind.sound

        XCTAssertNotEqual(notifications.iconName, background.iconName)
        XCTAssertNotEqual(notifications.title, background.title)
        XCTAssertNotEqual(notifications.body, background.body)
    }

    // MARK: - Helpers

    /// A loaded screen. `viewDidLoad` builds the cards, so `loadViewIfNeeded()`
    /// is enough — no window or layout pass is needed to count them.
    private func makeLoadedSUT() -> PermissionsViewController {
        let sut = PermissionsViewController()
        sut.loadViewIfNeeded()
        return sut
    }

    /// Cards in mounted order, found by type so the test survives a rename of
    /// the private stack property.
    private func mountedCards(of controller: UIViewController) -> [PermissionCardView] {
        var found: [PermissionCardView] = []
        var queue: [UIView] = [controller.view]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let card = view as? PermissionCardView {
                found.append(card)
                continue
            }
            queue.append(contentsOf: view.subviews)
        }
        return found
    }

    /// The card's title is its first label — title sits above the `meta`
    /// subtitle in the copy stack.
    private func title(of card: PermissionCardView) -> String? {
        labelTexts(in: card).first
    }

    private func labelTexts(in view: UIView) -> [String] {
        var texts: [String] = []
        var queue: [UIView] = view.subviews
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let label = next as? UILabel {
                if let text = label.text {
                    texts.append(text)
                } else if let attributed = label.attributedText {
                    texts.append(attributed.string)
                }
            }
            queue.append(contentsOf: next.subviews)
        }
        return texts
    }
}
