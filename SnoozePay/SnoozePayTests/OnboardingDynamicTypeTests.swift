import UIKit
import XCTest
@testable import SnoozePay

/// Dynamic Type, onboarding slice: the three onboarding pages, the
/// «Пропустить» pill and the components on them (#1111).
///
/// Same approach as `AlarmsListDynamicTypeTests`: every measurement overrides
/// the category explicitly, so nothing depends on what the simulator is set to.
/// The controller is laid out without a window, so no safe area depends on the
/// simulator model either; the cold-start test that does use a window compares
/// the window against itself.
///
/// The pages read no `UserDefaults` (only the finish buttons write them, and
/// these tests never tap one), and the controller gets its own notification
/// center, so nothing here touches `.standard` or the app's observers.
@MainActor
final class OnboardingDynamicTypeTests: XCTestCase {

    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
    private static let grownCategories: [UIContentSizeCategory] = [.extraLarge, .extraExtraExtraLarge, ax5]
    /// iPhone SE: 375pt wide and the dense compact-height layout (#244).
    private let small = CGSize(width: 375, height: 667)
    /// 375pt wide at full height: the h1 titles at the narrowest width.
    private let narrow = CGSize(width: 375, height: 812)
    private let wide = CGSize(width: 402, height: 874)

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Today's geometry

    /// Every label of every page, in page coordinates, as measured on main
    /// (`OnboardingTodaysGeometry`). At 375×812 only page 1, the one whose
    /// centred column used to depend on the order of layout passes.
    private func todaysPages(at size: CGSize) -> [[OnboardingTodaysGeometry.Pin]] {
        switch size {
        case small: return OnboardingTodaysGeometry.small
        case narrow: return [OnboardingTodaysGeometry.narrowPage1]
        default: return OnboardingTodaysGeometry.wide
        }
    }

    private func assertTodaysGeometry(
        of controller: OnboardingViewController, size: CGSize, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let name = "\(Int(size.width))×\(Int(size.height))"
        XCTAssertEqual(controller.pageViews.count, 3, file: file, line: line)
        for (index, pins) in todaysPages(at: size).enumerated() {
            let page = controller.pageViews[index]
            for (prefix, frame) in pins {
                let label = try label(startingWith: prefix, in: page)
                let actual = label.convert(label.bounds, to: page)
                for (got, want, edge) in [
                    (actual.minX, frame.minX, "x"), (actual.minY, frame.minY, "y"),
                    (actual.width, frame.width, "width"), (actual.height, frame.height, "height")
                ] {
                    XCTAssertEqual(
                        got, want, accuracy: 0.01, "\(name) page \(index + 1) «\(prefix)» \(edge) moved",
                        file: file, line: line
                    )
                }
            }
            XCTAssertEqual(
                page.scrollView.contentSize.height, page.scrollView.bounds.height, accuracy: 0.01,
                "\(name) page \(index + 1) scrolls at the default size", file: file, line: line
            )
        }
        let pill = try XCTUnwrap(descendants(of: OnboardingPenaltyPill.self, in: controller.pageViews[0]).first)
        XCTAssertEqual(pill.bounds.height, 30, accuracy: 0.01, "\(name): pill height", file: file, line: line)
        let skip = controller.skipButton.frame
        XCTAssertEqual(skip.minY, 16, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(skip.width, 111, accuracy: 0.01, "\(name): the skip pill changed width", file: file, line: line)
        XCTAssertEqual(skip.height, 31 + 1 / 3, accuracy: 0.01, file: file, line: line)
    }

    func testAtTheDefaultSizeEveryPageIsUnchanged() throws {
        for size in [small, narrow, wide] {
            let controller = onboarding(.large, size: size)
            try assertTodaysGeometry(of: controller, size: size)
            let titleRole = size == small ? AppTypography.h2 : AppTypography.h1
            for (page, key) in zip(controller.pageViews, ["page1.title", "page2.title", "page3.title"]) {
                let font = try attributedFont(of: label(startingWith: Localized.text("onboarding.\(key)"), in: page))
                XCTAssertEqual(font.pointSize, titleRole.pointSize, key)
                XCTAssertEqual(font.fontName, titleRole.fontName, key)
            }
            let skip = try XCTUnwrap(controller.skipButton.configuration?.attributedTitle?.font)
            XCTAssertEqual(skip.pointSize, AppTypography.buttonSm.pointSize)
        }
    }

    // MARK: - Grown

    /// XL, XXXL and AX5 on all three phones: the text grows (titles to 48pt at
    /// most, the rest to 2×), no label is clipped or broken mid-word, and a
    /// column that outgrows its page scrolls between the skip pill and the dots.
    func testGrownPagesKeepEveryWordWholeAndClearTheChrome() throws {
        for size in [small, narrow, wide] {
            for category in Self.grownCategories {
                let controller = onboarding(category, size: size)
                let name = "\(category.rawValue) at \(Int(size.width))×\(Int(size.height))"
                let regular = onboarding(.large, size: size)
                for (index, page) in controller.pageViews.enumerated() {
                    assertNothingClipped(in: page, "\(name) page \(index + 1)")
                    try assertColumnClearsTheChrome(of: page, in: controller, "\(name) page \(index + 1)")
                    let before = descendants(of: UILabel.self, in: regular.pageViews[index]).filter(\.isVisible)
                    let after = descendants(of: UILabel.self, in: page).filter(\.isVisible)
                    XCTAssertEqual(after.count, before.count, "\(name) page \(index + 1): labels came or went")
                    for (old, new) in zip(before, after) where old.text != "07:00" && old.text?.count != 1 {
                        let was = try attributedFont(of: old).pointSize
                        let now = try attributedFont(of: new).pointSize
                        XCTAssertGreaterThan(now, was, "\(name): «\(new.text ?? "")» did not grow")
                        XCTAssertLessThanOrEqual(now, was * AppTypography.maximumScale + 0.01)
                    }
                }
                for (page, key) in zip(controller.pageViews, ["page1.title", "page2.title", "page3.title"]) {
                    let text = Localized.text("onboarding.\(key)")
                    let title = try attributedFont(of: label(startingWith: text, in: page))
                    XCTAssertLessThanOrEqual(title.pointSize, OnboardingViewController.pageTitleMaximumPointSize, name)
                }
                // The clock is the page's illustration, as large as before.
                let clock = try label(startingWith: "07:00", in: controller.pageViews[0])
                XCTAssertEqual(clock.font.pointSize, size == small ? 64 : 96, name)
            }
        }
    }

    /// At AX5 no page fits: each one scrolls, and a drag that starts on an
    /// option card scrolls the page instead of staying with the card.
    func testAtAX5EveryPageScrollsAndADragFromAnOptionCardScrolls() throws {
        for size in [small, wide] {
            let controller = onboarding(Self.ax5, size: size)
            for (index, page) in controller.pageViews.enumerated() {
                XCTAssertGreaterThan(
                    page.scrollView.contentSize.height, page.scrollView.bounds.height + 1,
                    "page \(index + 1) at \(size.width) cannot scroll"
                )
            }
            let scroll = controller.pageViews[2].scrollView
            let card = try XCTUnwrap(controller.depositOptionViews.first)
            XCTAssertTrue(scroll.delaysContentTouches, "cards would highlight on every pan")
            XCTAssertTrue(scroll.canCancelContentTouches)
            XCTAssertTrue(scroll.touchesShouldCancel(in: card), "a drag from a card does not scroll")
        }
    }

    /// From XL the «ПОПУЛЯРНО» tag goes under its title and the amount under
    /// the description; below XL they stay beside, as today.
    func testFromXLTheDepositCardsStack() throws {
        for size in [small, wide] {
            for category in [UIContentSizeCategory.large] + Self.grownCategories {
                let controller = onboarding(category, size: size)
                let page = controller.pageViews[2]
                let name = "\(category.rawValue) at \(size.width)"
                let stacked = AppTypography.stacksDenseRows(category)
                for (index, card) in controller.depositOptionViews.enumerated() {
                    let description = try label(startingWith: "≈", in: card)
                    let amount = try XCTUnwrap(
                        descendants(of: UILabel.self, in: card).first { $0.text?.first?.isNumber == true }
                    )
                    let frame = { (view: UIView) in view.convert(view.bounds, to: page) }
                    if stacked {
                        XCTAssertGreaterThanOrEqual(
                            frame(amount).minY, frame(description).maxY, "\(name) card \(index): amount beside"
                        )
                        XCTAssertEqual(frame(amount).minX, frame(description).minX, accuracy: 0.5, name)
                    } else {
                        XCTAssertGreaterThan(frame(amount).minX, frame(description).maxX, "\(name) card \(index)")
                    }
                    XCTAssertLessThanOrEqual(frame(card).maxX, size.width - AppSpacing.sp4 + 0.5, name)
                }
                let title = try label(startingWith: Localized.text("onboarding.page3.option2_title"), in: page)
                let tag = try label(startingWith: "ПОПУЛЯРНО", in: page)
                if stacked {
                    XCTAssertGreaterThanOrEqual(
                        tag.convert(tag.bounds, to: page).minY, title.convert(title.bounds, to: page).maxY, name
                    )
                } else {
                    XCTAssertEqual(tag.frame.minX - title.frame.maxX, AppSpacing.sp2, accuracy: 0.5, name)
                }
                XCTAssertEqual(title.numberOfLines, 1)
            }
        }
    }

    /// Both directions on the same controller, the selection kept across the
    /// rebuild: grown at AX5, then back to the pinned geometry.
    func testThePagesFollowALiveCategoryChangeInBothDirections() throws {
        for size in [small, wide] {
            let controller = onboarding(.large, size: size)
            controller.handleDepositOptionTap(at: 2)
            override(controller, to: Self.ax5)
            layOut(controller)
            let title = try label(startingWith: Localized.text("onboarding.page3.title"), in: controller.pageViews[2])
            XCTAssertGreaterThan(try attributedFont(of: title).pointSize, AppTypography.h1.pointSize)
            XCTAssertGreaterThan(
                controller.pageViews[2].scrollView.contentSize.height, controller.pageViews[2].scrollView.bounds.height
            )
            XCTAssertEqual(controller.depositOptionViews.map(\.isSelectedOption), [false, false, true])
            let skip = try XCTUnwrap(controller.skipButton.configuration?.attributedTitle?.font)
            XCTAssertGreaterThan(skip.pointSize, AppTypography.buttonSm.pointSize, "the skip pill did not grow")
            for page in controller.pageViews {
                assertNothingClipped(in: page, "live AX5 at \(size.width)")
                try assertColumnClearsTheChrome(of: page, in: controller, "live AX5 at \(size.width)")
            }

            override(controller, to: .large)
            layOut(controller)
            controller.handleDepositOptionTap(at: 1)
            try assertTodaysGeometry(of: controller, size: size)
        }
    }

    // MARK: - Cold start in a window

    /// The app's path: the controller becomes a window's root with the
    /// category already set. Its first layout is today's at the default size —
    /// the same as after a live round trip through AX5 — and grown at AX5.
    func testAColdStartInAWindowIsTheSteadyStateAtTheDefaultSizeAndGrownAtAX5() throws {
        let (cold, window) = coldStart(.large, size: wide)
        let first = labelFrames(of: cold)
        XCTAssertEqual(first.count, 27)
        window.traitOverrides.preferredContentSizeCategory = Self.ax5
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        let body = try label(startingWith: Localized.text("onboarding.page1.body"), in: cold.pageViews[0])
        XCTAssertGreaterThan(body.font.pointSize, AppTypography.bodyLg.pointSize, "the change did not reach the pages")
        window.traitOverrides.preferredContentSizeCategory = .large
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        let steady = labelFrames(of: cold)
        XCTAssertEqual(steady.count, first.count)
        for (lhs, rhs) in zip(first, steady) {
            XCTAssertEqual(lhs.text, rhs.text)
            XCTAssertEqual(lhs.frame.minY, rhs.frame.minY, accuracy: 0.01, "«\(lhs.text)» moved after a round trip")
            XCTAssertEqual(lhs.frame.height, rhs.frame.height, accuracy: 0.01, "«\(lhs.text)»")
            XCTAssertEqual(lhs.frame.minX, rhs.frame.minX, accuracy: 0.01, "«\(lhs.text)»")
        }

        let (grown, _) = coldStart(Self.ax5, size: wide)
        let title = try label(startingWith: Localized.text("onboarding.page1.title"), in: grown.pageViews[0])
        XCTAssertGreaterThan(try attributedFont(of: title).pointSize, AppTypography.h1.pointSize, "cold AX5 title")
        for page in grown.pageViews {
            assertNothingClipped(in: page, "cold AX5")
            try assertColumnClearsTheChrome(of: page, in: grown, "cold AX5")
        }
    }

    // MARK: - Assertions

    /// The column starts below the floating skip pill and ends above the dots
    /// — measured at the top of the content, where the page opens.
    private func assertColumnClearsTheChrome(
        of page: OnboardingPageView, in controller: OnboardingViewController, _ name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let column = try XCTUnwrap(page.content.subviews.first, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            column.frame.minY, controller.skipButton.frame.maxY + AppSpacing.sp2 - 0.5,
            "\(name): the column starts under the skip pill", file: file, line: line
        )
        let dotsInset = controller.scrollView.frame.maxY - controller.dotsStack.frame.minY
        XCTAssertLessThanOrEqual(
            column.frame.maxY, page.content.bounds.height - dotsInset - AppSpacing.sp2 + 0.5,
            "\(name): the column ends under the dots", file: file, line: line
        )
    }

    private func assertNothingClipped(
        in page: UIView, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let labels = descendants(of: UILabel.self, in: page).filter(\.isVisible)
        XCTAssertGreaterThanOrEqual(labels.count, 4, "\(name): too few labels to say anything", file: file, line: line)
        for label in labels {
            XCTAssertFalse(
                isClipped(label), "\(name): «\(label.text ?? "")» is clipped: \(label.bounds)", file: file, line: line
            )
        }
    }

    // MARK: - Hosting

    private func onboarding(_ category: UIContentSizeCategory, size: CGSize) -> OnboardingViewController {
        let controller = OnboardingViewController(
            priceContextSource: { .scale(.rouble) }, notificationCenter: NotificationCenter()
        )
        controller.traitOverrides.preferredContentSizeCategory = category
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(origin: .zero, size: size)
        layOut(controller)
        XCTAssertEqual(controller.traitCollection.preferredContentSizeCategory, category, "override did not land")
        return controller
    }

    private func layOut(_ controller: OnboardingViewController) {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    private func override(_ controller: OnboardingViewController, to category: UIContentSizeCategory) {
        controller.traitOverrides.preferredContentSizeCategory = category
        controller.updateTraitsIfNeeded()
        XCTAssertEqual(controller.traitCollection.preferredContentSizeCategory, category, "override did not land")
    }

    private func coldStart(
        _ category: UIContentSizeCategory, size: CGSize
    ) -> (OnboardingViewController, UIWindow) {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.traitOverrides.preferredContentSizeCategory = category
        hostWindows.append(window)
        let controller = OnboardingViewController(
            priceContextSource: { .scale(.rouble) }, notificationCenter: NotificationCenter()
        )
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        XCTAssertEqual(controller.traitCollection.preferredContentSizeCategory, category)
        return (controller, window)
    }

    // MARK: - Helpers

    private func labelFrames(of controller: OnboardingViewController) -> [(text: String, frame: CGRect)] {
        controller.pageViews.flatMap { page in
            descendants(of: UILabel.self, in: page).filter(\.isVisible).map {
                ($0.text ?? "", $0.convert($0.bounds, to: page))
            }
        }
    }

    private func label(startingWith prefix: String, in root: UIView) throws -> UILabel {
        let matches = descendants(of: UILabel.self, in: root).filter {
            $0.isVisible && ($0.text ?? "").hasPrefix(prefix)
        }
        XCTAssertEqual(matches.count, 1, "«\(prefix)» does not pick one label")
        return try XCTUnwrap(matches.first, "no label «\(prefix)»")
    }

    /// The font the label actually draws — the attributed run's, where one is set.
    private func attributedFont(of label: UILabel) throws -> UIFont {
        let font = label.attributedText.flatMap { text in
            text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont : nil
        }
        return try XCTUnwrap(font ?? label.font)
    }

    /// As in `AlarmsListDynamicTypeTests`: measured against unlimited lines at
    /// the label's width, and a wrapping label is clipped too when one of its
    /// words is wider than the label — UIKit then breaks it mid-word.
    private func isClipped(_ label: UILabel) -> Bool {
        let unlimited = label.textRect(
            forBounds: CGRect(x: 0, y: 0, width: label.bounds.width, height: .greatestFiniteMagnitude),
            limitedToNumberOfLines: 0
        )
        if unlimited.height > label.bounds.height + 0.5 { return true }
        return label.numberOfLines != 1 && widestWord(of: label) > label.bounds.width + 0.5
    }

    private func widestWord(of label: UILabel) -> CGFloat {
        guard let text = label.attributedText, text.length > 0 else { return 0 }
        let attributes = text.attributes(at: 0, effectiveRange: nil)
        // Only where UIKit may break a line: U+202F and U+00A0 keep "1 000 ₽" one word.
        return text.string.split(whereSeparator: { $0 == " " || $0.isNewline }).map { word in
            NSAttributedString(string: String(word), attributes: attributes).size().width
        }.max() ?? 0
    }

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        root.subviews.flatMap { [$0 as? T].compactMap { $0 } + descendants(of: type, in: $0) }
    }
}

private extension UIView {
    /// Shown, with something to show: a hidden tag or ancestor does not count.
    var isVisible: Bool {
        var view: UIView? = self
        while let current = view {
            if current.isHidden { return false }
            view = current.superview
        }
        return !((self as? UILabel)?.text ?? "x").isEmpty
    }
}

/// Onboarding geometry measured on main (d40b298a), before #1111 touched it,
/// with the harness above at the default category. A label is found by the
/// start of its text, which must be unique on its page.
private enum OnboardingTodaysGeometry {
    typealias Pin = (prefix: String, frame: CGRect)

    private static let title1 = Localized.text("onboarding.page1.title")
    private static let body1 = Localized.text("onboarding.page1.body")
    private static let caps2 = Localized.text("onboarding.page2.caps")
    private static let title2 = Localized.text("onboarding.page2.title")
    private static let caps3 = Localized.text("onboarding.page3.caps")
    private static let title3 = Localized.text("onboarding.page3.title")

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// 375×667, the compact layout.
    static var small: [[Pin]] {
        [
            [("07:00", rect(91 + 2 / 3, 125 + 2 / 3, 192, 84 + 2 / 3)),
             ("−50", rect(166 + 1 / 3, 228, 42 + 1 / 3, 18 + 2 / 3)),
             (title1, rect(124 + 2 / 3, 272 + 1 / 3, 125 + 2 / 3, 65 + 2 / 3)),
             (body1, rect(58 + 1 / 3, 352, 258 + 1 / 3, 61 + 2 / 3))],
            [(caps2, rect(16, 123 + 2 / 3, 343, 16 + 2 / 3)),
             (title2, rect(16, 148 + 1 / 3, 343, 65 + 2 / 3)),
             ("1", rect(16, 230, 32, 32)), ("Положили", rect(62, 230, 297, 23 + 1 / 3)),
             ("Это запас", rect(62, 255 + 1 / 3, 297, 35 + 2 / 3)),
             ("2", rect(16, 301, 32, 32)), ("Поспать", rect(62, 301, 297, 23 + 1 / 3)),
             ("Каждый раз", rect(62, 326 + 1 / 3, 297, 18)),
             ("3", rect(16, 354 + 1 / 3, 32, 32)), ("Встали", rect(62, 354 + 1 / 3, 297, 23 + 1 / 3)),
             ("Баланс продолжает", rect(62, 379 + 2 / 3, 297, 35 + 2 / 3))],
            [(caps3, rect(16, 91 + 2 / 3, 343, 16 + 2 / 3)),
             (title3, rect(16, 116 + 1 / 3, 343, 65 + 2 / 3)),
             ("Попробовать", rect(34, 210, 113, 23 + 1 / 3)), ("≈ 5", rect(34, 235 + 1 / 3, 234 + 2 / 3, 18)),
             ("250", rect(280 + 2 / 3, 218 + 1 / 3, 60 + 1 / 3, 26 + 2 / 3)),
             ("Серьёзно", rect(34, 283 + 1 / 3, 83, 23 + 1 / 3)),
             ("ПОПУЛЯРНО", rect(125, 288 + 1 / 3, 73 + 2 / 3, 13 + 2 / 3)),
             ("≈ 10", rect(34, 308 + 2 / 3, 234 + 2 / 3, 35 + 2 / 3)),
             ("500", rect(280 + 2 / 3, 300 + 2 / 3, 60 + 1 / 3, 26 + 2 / 3)),
             ("Решительно", rect(34, 374 + 1 / 3, 105, 23 + 1 / 3)),
             ("≈ 20", rect(34, 399 + 2 / 3, 210 + 2 / 3, 35 + 2 / 3)),
             ("1", rect(256 + 2 / 3, 391 + 2 / 3, 84 + 1 / 3, 26 + 2 / 3))]
        ]
    }

    /// 402×874.
    static var wide: [[Pin]] {
        [
            [("07:00", rect(57, 181, 288, 127)),
             ("−50", rect(180, 333 + 2 / 3, 42 + 1 / 3, 18 + 2 / 3)),
             (title1, rect(115 + 1 / 3, 394, 171 + 2 / 3, 87 + 2 / 3)),
             (body1, rect(66 + 1 / 3, 495 + 2 / 3, 269 + 1 / 3, 69 + 2 / 3))],
            [(caps2, rect(16, 213, 370, 16 + 2 / 3)),
             (title2, rect(16, 237 + 2 / 3, 370, 87 + 2 / 3)),
             ("1", rect(16, 357 + 1 / 3, 32, 32)), ("Положили", rect(62, 357 + 1 / 3, 324, 23 + 1 / 3)),
             ("Это запас", rect(62, 382 + 2 / 3, 324, 18)),
             ("2", rect(16, 414 + 2 / 3, 32, 32)), ("Поспать", rect(62, 414 + 2 / 3, 324, 23 + 1 / 3)),
             ("Каждый раз", rect(62, 440, 324, 18)),
             ("3", rect(16, 472, 32, 32)), ("Встали", rect(62, 472, 324, 23 + 1 / 3)),
             ("Баланс продолжает", rect(62, 497 + 1 / 3, 324, 35 + 2 / 3))],
            [(caps3, rect(16, 175, 370, 16 + 2 / 3)),
             (title3, rect(16, 199 + 2 / 3, 370, 87 + 2 / 3)),
             ("Попробовать", rect(34, 327 + 1 / 3, 113, 23 + 1 / 3)), ("≈ 5", rect(34, 352 + 2 / 3, 261 + 2 / 3, 18)),
             ("250", rect(307 + 2 / 3, 335 + 2 / 3, 60 + 1 / 3, 26 + 2 / 3)),
             ("Серьёзно", rect(34, 410 + 2 / 3, 83, 23 + 1 / 3)),
             ("ПОПУЛЯРНО", rect(125, 415 + 2 / 3, 73 + 2 / 3, 13 + 2 / 3)),
             ("≈ 10", rect(34, 436, 261 + 2 / 3, 18)),
             ("500", rect(307 + 2 / 3, 419, 60 + 1 / 3, 26 + 2 / 3)),
             ("Решительно", rect(34, 494, 105, 23 + 1 / 3)),
             ("≈ 20", rect(34, 519 + 1 / 3, 237 + 2 / 3, 35 + 2 / 3)),
             ("1", rect(283 + 2 / 3, 511 + 1 / 3, 84 + 1 / 3, 26 + 2 / 3))]
        ]
    }

    /// 375×812, page 1 in a window on main (the windowless layout on main
    /// collapsed its title and body to one glyph a line — #269).
    static var narrowPage1: [Pin] {
        [("07:00", rect(43 + 2 / 3, 150, 288, 127)),
         ("−50", rect(166 + 1 / 3, 302 + 2 / 3, 42 + 1 / 3, 18 + 2 / 3)),
         (title1, rect(101 + 2 / 3, 363, 171 + 2 / 3, 87 + 2 / 3)),
         (body1, rect(53, 464 + 2 / 3, 269 + 1 / 3, 69 + 2 / 3))]
    }
}
