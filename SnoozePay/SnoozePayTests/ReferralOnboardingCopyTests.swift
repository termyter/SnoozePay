import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that #600 moved out of `ReferralViewController` and
/// `OnboardingViewController+Pages` into `Localizable.xcstrings`.
///
/// A missed key on these two screens is silent in a way a compiler cannot help
/// with: `Localized.text("referral.section.friends")` returns the key itself,
/// the caps label renders `referral.section.friends`, nothing throws and the
/// build ships. So the tests come in two layers:
///
///  1. **Catalogue layer** — every key this migration introduced exists and is
///     not equal to itself. Catches a typo made while editing the catalogue.
///  2. **Screen layer** — the real view hierarchies are mounted and every
///     string they render is checked against the key list. Catches the other
///     half, a typo made at the *call site*, which layer 1 cannot see because
///     the catalogue is perfectly fine in that case.
///
/// Layer 2 is why the screens are built rather than asserted on in the
/// abstract: a key rendered on screen looks like `onboarding.page2.caps`, and
/// that shape — a dotted lowercase ASCII token where copy belongs — is exactly
/// what is asserted against.
final class ReferralOnboardingCopyTests: XCTestCase {

    /// iPhone 17 points, matching `OnboardingDepositOptionLayoutTests` — the
    /// onboarding pager needs a real window to build its pages.
    private let screen = CGSize(width: 402, height: 874)

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // MARK: - The keys this migration owns

    /// Written out rather than derived from the catalogue on purpose: a list
    /// generated from the file under test would agree with any mistake in it.
    ///
    /// One key #600 introduced is deliberately absent: `referral.applied.confirm`
    /// held the dismiss button of the «Код применён» alert and spelled it Latin
    /// «OK» while the app's other acknowledge buttons read «Ок» through
    /// `common.button.ok`. #751 deleted it and sent the call site to the shared
    /// key, so the button is now pinned by `AlertButtonLocalizationTests` — the
    /// domain list here would only reintroduce it.
    private static let referralKeys = [
        "referral.applied.message",
        "referral.applied.title",
        "referral.button.apply",
        "referral.button.copy",
        "referral.button.share",
        "referral.field.friend_code_placeholder",
        "referral.friend_1.initial",
        "referral.friend_1.name",
        "referral.friend_1.status",
        "referral.friend_2.initial",
        "referral.friend_2.name",
        "referral.friend_2.status",
        "referral.friend_2.trailing",
        "referral.friend_3.initial",
        "referral.friend_3.name",
        "referral.friend_3.status",
        "referral.friend_3.trailing",
        "referral.friend_code.hint",
        "referral.hero.body",
        "referral.hero.caps",
        "referral.hero.headline",
        "referral.section.friend_code",
        "referral.section.friends",
        "referral.section.personal_code",
        "referral.share.message",
        "referral.title"
    ]

    private static let onboardingKeys = [
        "onboarding.button.deposit",
        "onboarding.button.next",
        "onboarding.page1.body",
        "onboarding.page1.title",
        "onboarding.page2.caps",
        "onboarding.page2.step1_body",
        "onboarding.page2.step1_title",
        "onboarding.page2.step2_body",
        "onboarding.page2.step2_title",
        "onboarding.page2.step3_body",
        "onboarding.page2.step3_title",
        "onboarding.page2.title",
        "onboarding.page3.caps",
        "onboarding.page3.title"
    ]

    private static var allKeys: [String] { referralKeys + onboardingKeys }

    // MARK: - Layer 1: the catalogue

    func testEveryMigratedKeyResolvesToCopy() {
        for key in Self.allKeys {
            XCTAssertNotNil(Localized.optionalText(key), "missing catalogue key: \(key)")
            XCTAssertNotEqual(
                Localized.text(key), key,
                "\(key) resolves to itself — the entry is absent or holds the key as its value"
            )
        }
    }

    // MARK: - Layer 2a: the referral screen

    func testReferralScreenRendersCopyRatherThanKeys() {
        let controller = mount(ReferralViewController())

        let rendered = strings(in: controller.view) + [controller.title ?? ""]
        assertNoKeysLeaked(in: rendered)

        for expected in [
            Localized.text("referral.hero.caps"),
            Localized.text("referral.section.personal_code"),
            Localized.text("referral.section.friend_code"),
            Localized.text("referral.section.friends"),
            Localized.text("referral.friend_1.name"),
            Localized.text("referral.friend_2.status"),
            Localized.text("referral.friend_3.trailing")
        ] {
            XCTAssertTrue(rendered.contains(expected), "referral screen never renders «\(expected)»")
        }
        XCTAssertEqual(controller.title, Localized.text("referral.title"))
    }

    /// The headline substitutes one amount into two positions, which is the
    /// only reason it uses `%1$@` twice instead of two plain `%@`.
    func testReferralHeadlineRepeatsTheSingleAmount() {
        let amount = MoneyFormatter.string(200)
        let headline = Localized.format("referral.hero.headline", amount)

        XCTAssertEqual(headline.components(separatedBy: amount).count - 1, 2, "expected two amounts: \(headline)")
        XCTAssertTrue(headline.contains("\n"), "the two-line break is the design: \(headline)")
    }

    /// The share text takes two different arguments, so a swapped pair would
    /// read as «code … +WAKEUP-7K2» and still compile.
    func testReferralShareTextKeepsItsArgumentsInOrder() throws {
        let message = Localized.format("referral.share.message", "WAKEUP-7K2", MoneyFormatter.string(200))

        let code = try XCTUnwrap(message.range(of: "WAKEUP-7K2"), "the code never reached the share text")
        let bonus = try XCTUnwrap(
            message.range(of: MoneyFormatter.string(200)),
            "the bonus never reached the share text"
        )
        XCTAssertLessThan(code.lowerBound, bonus.lowerBound, "the code comes before the bonus: \(message)")
    }

    // MARK: - Layer 2b: the onboarding pages

    func testOnboardingPagesRenderCopyRatherThanKeys() {
        let controller = mount(OnboardingViewController())

        let rendered = controller.pageViews.flatMap { strings(in: $0) }
        assertNoKeysLeaked(in: rendered)

        for expected in [
            Localized.text("onboarding.page1.title"),
            Localized.text("onboarding.page1.body"),
            Localized.text("onboarding.page2.caps"),
            Localized.text("onboarding.page2.title"),
            Localized.text("onboarding.page2.step1_body"),
            Localized.text("onboarding.page3.caps"),
            Localized.text("onboarding.page3.title")
        ] {
            XCTAssertTrue(rendered.contains(expected), "onboarding never renders «\(expected)»")
        }
    }

    /// Step titles 1 and 2 interpolate a formatted amount, so they are
    /// compared against the same `Localized.format` rendering the screen uses
    /// — a plain literal here would freeze today's money formatting into the
    /// test and break on #559.
    func testOnboardingMechanicsStepsCarryTheirAmounts() {
        let controller = mount(OnboardingViewController())
        let rendered = controller.pageViews.flatMap { strings(in: $0) }

        let deposited = Localized.format("onboarding.page2.step1_title", MoneyFormatter.string(500))
        let penalty = Localized.format("onboarding.page2.step2_title", MoneyFormatter.string(50))
        XCTAssertTrue(rendered.contains(deposited), "step 1 title missing: \(deposited)")
        XCTAssertTrue(rendered.contains(penalty), "step 2 title missing: \(penalty)")
        XCTAssertTrue(deposited.contains(MoneyFormatter.string(500)))
        XCTAssertTrue(penalty.contains(MoneyFormatter.string(50)))
    }

    /// `SnoozePayUITests/OnboardingFlowUITests` finds the advance CTA by this
    /// very text, so the catalogue value and the E2E expectation are one fact.
    ///
    /// Read through `accessibilityLabel`: `SPButton` keeps its title in a
    /// private `UILabel` and exposes itself as a single accessibility element
    /// whose label is `title` joined with the optional amount suffix — which
    /// is also the string the UI test matches on.
    func testOnboardingPrimaryCTAComesFromTheCatalogue() {
        let controller = mount(OnboardingViewController())

        XCTAssertEqual(controller.primaryButton.accessibilityLabel, Localized.text("onboarding.button.next"))

        controller.rebuildDepositCTA()
        let deposit = controller.primaryButton.accessibilityLabel ?? ""
        XCTAssertTrue(
            deposit.hasPrefix(Localized.text("onboarding.button.deposit")),
            "the page-3 CTA reads «\(deposit)», expected the catalogue verb followed by the amount"
        )
    }

    // MARK: - Helpers

    private func mount<T: UIViewController>(_ controller: T) -> T {
        let host = UIWindow(frame: CGRect(origin: .zero, size: screen))
        host.rootViewController = controller
        host.isHidden = false
        window = host
        controller.loadViewIfNeeded()
        host.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        return controller
    }

    /// Every piece of text the subtree renders — plain labels, attributed
    /// labels (the caps captions are attributed) and field placeholders.
    private func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        if let field = view as? UITextField {
            found.append(contentsOf: [field.text, field.placeholder].compactMap { $0 })
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }

    /// A key that reached the screen looks like `referral.section.friends`.
    private func assertNoKeysLeaked(in rendered: [String], file: StaticString = #filePath, line: UInt = #line) {
        for key in Self.allKeys where rendered.contains(key) {
            XCTFail("«\(key)» rendered as its own key — the catalogue lookup missed", file: file, line: line)
        }
    }
}
