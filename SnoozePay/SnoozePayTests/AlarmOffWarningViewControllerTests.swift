import UIKit
import XCTest
@testable import SnoozePay

/// Load-time guarantees for the "alarm off" warning sheet (#514).
///
/// This screen shipped with a fatal layout bug and carried it silently,
/// because nothing in the suite had ever *opened* it:
///
/// ```
/// SIGABRT / NSGenericException
/// Unable to activate constraint … no common ancestor
///     AlarmOffWarningViewController.makeTopBar
/// ```
///
/// `makeTopBar` activated `spacer.widthAnchor == closeButton.widthAnchor`
/// one line before the `UIStackView` that becomes their common ancestor was
/// created. Autolayout resolves the common ancestor **at activation time**,
/// not at layout time, so the screen died before its first frame — 100%
/// reproducible, invisible to every existing test.
///
/// `testScreenLoads_withoutRaising` is the regression net: it is the cheapest
/// possible assertion (`loadViewIfNeeded()`) and it would have failed on the
/// original code. The layout tests below exist so the fix can't be "passed"
/// by simply deleting the constraint — the mirrored width is what centres the
/// «ВНИМАНИЕ» caps, so its *effect* is pinned, not just its absence of crash.
final class AlarmOffWarningViewControllerTests: XCTestCase {

    /// iPhone 15 Pro portrait — the reference frame used by the other layout
    /// suites in this target.
    private let referenceSize = CGSize(width: 393, height: 852)

    /// Windows are retained for the lifetime of the test: a `UIWindow` that
    /// nothing holds is free to deallocate mid-assertion and take the hosted
    /// hierarchy with it.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - The regression

    /// The whole bug, in one line. On the pre-fix code `loadViewIfNeeded()`
    /// raises `NSGenericException` from `makeTopBar` and this test aborts.
    func testScreenLoads_withoutRaising() {
        let sut = AlarmOffWarningViewController()
        sut.loadViewIfNeeded()
        XCTAssertNotNil(sut.viewIfLoaded, "the sheet must survive viewDidLoad")
    }

    /// The crash was in `viewDidLoad`, so it fired in both themes. Loading
    /// under each style also exercises `refreshHeroTheme()`, which re-resolves
    /// the two cached `cgColor` payloads on the hero badge.
    func testScreenLoads_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let sut = AlarmOffWarningViewController()
            sut.overrideUserInterfaceStyle = style
            sut.loadViewIfNeeded()
            XCTAssertNotNil(sut.viewIfLoaded, "sheet failed to load in \(style)")
        }
    }

    /// A full layout pass is where an *unsatisfiable* constraint set would
    /// show up (as a broken-constraint log and a collapsed frame), so drive
    /// one and assert the sheet actually occupies the window.
    func testScreenSurvivesLayoutPass() {
        let sut = AlarmOffWarningViewController()
        let window = hostInWindow(sut)
        window.layoutIfNeeded()

        XCTAssertEqual(sut.view.bounds.size, window.bounds.size, "root view did not fill the window")
        XCTAssertFalse(sut.view.subviews.isEmpty, "layout pass produced an empty hierarchy")
    }

    // MARK: - What the constraint is FOR

    /// The moved constraint mirrors the close button's width onto the trailing
    /// spacer. Deleting it would also make the crash go away, so pin the
    /// measurement: after layout the two must be the same non-zero width.
    func testTrailingSpacer_mirrorsCloseButtonWidth() {
        let sut = AlarmOffWarningViewController()
        let window = hostInWindow(sut)
        window.layoutIfNeeded()

        guard let row = topBarRow(in: sut.view) else {
            return XCTFail("top bar row not found — the sheet's structure changed")
        }
        let closeButton = row.arrangedSubviews[0]
        let spacer = row.arrangedSubviews[2]

        XCTAssertGreaterThan(closeButton.bounds.width, 0, "close button collapsed to zero width")
        XCTAssertEqual(
            spacer.bounds.width,
            closeButton.bounds.width,
            accuracy: 0.5,
            "trailing spacer must mirror the close button so «ВНИМАНИЕ» reads centred"
        )
    }

    /// The mirrored spacer exists only to centre the caps label. Assert the
    /// outcome rather than the mechanism, so a future re-implementation of the
    /// top bar is still held to the same visual contract.
    func testCapsLabel_isHorizontallyCentredInTheTopBar() {
        let sut = AlarmOffWarningViewController()
        let window = hostInWindow(sut)
        window.layoutIfNeeded()

        guard let row = topBarRow(in: sut.view) else {
            return XCTFail("top bar row not found — the sheet's structure changed")
        }
        guard let caps = row.arrangedSubviews[1] as? UILabel else {
            return XCTFail("top bar's middle slot is no longer the caps label")
        }

        XCTAssertEqual(caps.attributedText?.string, "ВНИМАНИЕ")
        XCTAssertEqual(
            caps.center.x,
            row.bounds.midX,
            accuracy: 2.0,
            "caps label drifted off the row's centre"
        )
    }

    // MARK: - Helpers

    /// Mount the controller in a sized window. A real window is what makes the
    /// safe-area guides and trait propagation behave like they do on device.
    private func hostInWindow(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: referenceSize))
        hostWindows.append(window)
        window.rootViewController = controller
        window.isHidden = false
        controller.loadViewIfNeeded()
        window.setNeedsLayout()
        return window
    }

    /// The top bar is the horizontal stack whose leading slot is the «Закрыть»
    /// `SPButton`. Located by accessibility label because `SPButton` renders
    /// its title into private subviews.
    private func topBarRow(in root: UIView) -> UIStackView? {
        guard let closeButton = firstSubview(in: root, where: {
            $0 is SPButton && $0.accessibilityLabel == "Закрыть"
        }) else {
            return nil
        }
        guard let row = closeButton.superview as? UIStackView,
              row.axis == .horizontal,
              row.arrangedSubviews.count == 3,
              row.arrangedSubviews.first === closeButton else {
            return nil
        }
        return row
    }

    private func firstSubview(in root: UIView, where match: (UIView) -> Bool) -> UIView? {
        for child in root.subviews {
            if match(child) { return child }
            if let found = firstSubview(in: child, where: match) { return found }
        }
        return nil
    }
}
