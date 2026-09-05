import XCTest
@testable import SnoozePay

/// The «Готово» button of the sound and theme pickers must opt out of the
/// navigation bar's shared glass capsule, exactly as the create/edit alarm
/// screen already does (#649 → #666).
///
/// Both are `SPButton(variant: .quiet, size: .sm)`, and unlike the `.money`
/// button of #649 their contrast is not at stake: the quiet pill measures
/// 14.46:1 against `bg0` with the capsule and without it. What the capsule
/// costs here is the shape — it draws a second, wider ring around a control
/// that already carries its own `--sp-white-06` fill, so two buttons that the
/// canon draws identically (`SPMore.jsx:313`, `SPMore2.jsx:340`,
/// `SPScreensV2.jsx:525`) rendered differently depending on which screen you
/// were on.
///
/// Like `CreateAlarmBarButtonGlassTests`, these assertions are structural
/// rather than photometric on purpose: the extra ring is painted by the
/// compositor, so no property a unit test can read changes when it appears.
/// Dropping `hidesSharedBackground` is the single change that brings it back,
/// so that is what is pinned.
final class AlarmPickerBarButtonGlassTests: XCTestCase {

    /// Both screens build their header in `viewDidLoad`, so loading the view is
    /// all these assertions need. No window and no `layoutIfNeeded`, following
    /// `AlarmEditorCopyTests`: forcing a layout pass on the theme picker
    /// renders every tile in the grid and buys nothing here.
    private func loaded<T: UIViewController>(_ viewController: T) -> T {
        viewController.loadViewIfNeeded()
        return viewController
    }

    private func makeSoundPicker() -> SoundPickerViewController {
        SoundPickerViewController(
            sounds: SoundCatalogue.entries,
            selectedID: SoundCatalogue.entries.first?.id ?? "",
            onSelect: { _ in },
            previewSound: { _ in }
        )
    }

    // MARK: - Sound picker

    func testSoundPickerDoneButtonOptsOutOfTheSharedGlass() {
        let item = loaded(makeSoundPicker()).navigationItem.rightBarButtonItem
        XCTAssertNotNil(item?.customView, "«Готово» should be a custom-view item")
        XCTAssertTrue(
            item?.hidesSharedBackground == true,
            "The capsule draws a second ring around the quiet pill's own fill"
        )
    }

    // MARK: - Theme picker

    func testThemePickerDoneButtonOptsOutOfTheSharedGlass() {
        let picker = AlarmThemePickerViewController(currentTheme: .dawn, onSelect: { _ in })
        let item = loaded(picker).navigationItem.rightBarButtonItem
        XCTAssertNotNil(item?.customView, "«Готово» should be a custom-view item")
        XCTAssertTrue(
            item?.hidesSharedBackground == true,
            "The capsule draws a second ring around the quiet pill's own fill"
        )
    }

    // MARK: - The shared helper

    /// The three screens now share one wrapper rather than three copies of it,
    /// which is what keeps a fourth screen from re-introducing the defect by
    /// reaching for `UIBarButtonItem(customView:)` directly.
    func testSharedHelperOptsTheItemOutAndKeepsTheControl() {
        let control = SPButton(title: "Готово", variant: .quiet, size: .sm)
        let item = AppNavigationBarStyle.barItem(for: control)
        XCTAssertTrue(item.hidesSharedBackground)
        XCTAssertIdentical(item.customView, control)
    }
}
