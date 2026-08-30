import XCTest
@testable import SnoozePay

/// The nav-bar controls of the create/edit alarm screen must opt out of the
/// bar's shared glass capsule (#649).
///
/// iOS 26 paints that capsule OVER a bar-button item's custom view, sampling
/// what is behind it. On a control that already draws its own filled
/// background, the result is a translucent copy of our own fill laid on top of
/// our own ink. Measured from simulator screenshots of «Готово»:
///
/// | theme | before | after |
/// |---|---|---|
/// | dark  | ink `#0D7351` on `#13BD84` — **2.41:1** | ink `#052016` — **7.05:1** |
/// | light | ink `#B7FFEE` on `#096B4A` — 5.77:1     | ink `#FFFFFF` — 6.53:1     |
///
/// The dark figure is under WCAG's 3:1 floor for large text, on the terminal
/// action of the screen.
///
/// These assertions are structural rather than photometric on purpose: the
/// defect lives in the compositor, so nothing a unit test can measure — the
/// label's `textColor` reads `#052016` in both builds. Dropping
/// `hidesSharedBackground` is the single change that brings the bug back, so
/// that is what is pinned here. The contrast numbers above come from real
/// screenshots and are recorded in the PR.
final class CreateAlarmBarButtonGlassTests: XCTestCase {

    private func hosted(alarm: Alarm?) -> CreateAlarmViewController {
        let sut = CreateAlarmViewController(alarm: alarm)
        let nav = UINavigationController(rootViewController: sut)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.isHidden = false
        sut.loadViewIfNeeded()
        window.layoutIfNeeded()
        return sut
    }

    private func sample() -> Alarm {
        Alarm(time: Date(), repeatDays: [1, 2, 3], name: "Работа", penaltyAmount: 50)
    }

    // MARK: - Create mode

    func testCreateModeSaveButtonOptsOutOfTheSharedGlass() {
        let item = hosted(alarm: nil).navigationItem.rightBarButtonItem
        XCTAssertNotNil(item?.customView, "«Готово» should be a custom-view item")
        XCTAssertTrue(
            item?.hidesSharedBackground == true,
            "The glass capsule halves the money button's ink contrast (2.41:1)"
        )
    }

    func testCreateModeCloseChipOptsOutOfTheSharedGlass() {
        let item = hosted(alarm: nil).navigationItem.leftBarButtonItem
        XCTAssertTrue(
            item?.hidesSharedBackground == true,
            "The capsule draws a second ring around the round close chip"
        )
    }

    // MARK: - Edit mode
    //
    // Edit builds a different pair — «Отмена» instead of the close chip — from
    // the same helper, and it is the mode where the terminal action is
    // «Сохранить». Both are checked so a future split of the two paths cannot
    // fix one and leave the other.

    func testEditModeSaveButtonOptsOutOfTheSharedGlass() {
        let item = hosted(alarm: sample()).navigationItem.rightBarButtonItem
        XCTAssertNotNil(item?.customView, "«Сохранить» should be a custom-view item")
        XCTAssertTrue(item?.hidesSharedBackground == true)
    }

    func testEditModeCancelButtonOptsOutOfTheSharedGlass() {
        let item = hosted(alarm: sample()).navigationItem.leftBarButtonItem
        XCTAssertTrue(item?.hidesSharedBackground == true)
    }
}
