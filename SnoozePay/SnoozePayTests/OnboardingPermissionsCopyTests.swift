import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that #600 moved out of the rest of `ViewControllers/Onboarding`
/// — the deposit presets and chrome buttons of `OnboardingViewController`, the
/// `ПОПУЛЯРНО` tag in `OnboardingComponents`, the whole permissions screen and
/// the splash tagline — into `Localizable.xcstrings`.
///
/// Continues `ReferralOnboardingCopyTests` (#610) and adds the check the issue
/// actually asks for: **the text on screen did not change**. A migration that
/// resolves cleanly but drops a `ё`, a `·` or a trailing full stop is invisible
/// to a key-exists assertion and invisible in review, so the former literals
/// are written out here verbatim and compared byte for byte. They are typed
/// from the pre-migration source, not copied from the catalogue — a value
/// derived from the file under test would agree with any mistake in it.
///
/// The second half is the same two-layer shape as #610: mount the real view
/// hierarchies and check that what they render is copy rather than a dotted
/// lowercase key, which is what `Localized.text` returns on a miss.
final class OnboardingPermissionsCopyTests: XCTestCase {

    /// iPhone 17 points, matching `OnboardingDepositOptionLayoutTests` — the
    /// onboarding pager needs a real window to build its pages.
    private let screen = CGSize(width: 402, height: 874)

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // MARK: - The keys this migration owns, and the literals they replaced

    /// `onboarding.page3.option1_body` is absent on purpose: it takes an
    /// argument and is pinned by `testFirstPresetKeepsTheAmountItInterpolates`.
    private static let copyBeforeMigration: [String: String] = [
        "common.button.done": "Готово",
        "onboarding.button.later": "Позже — попробовать без баланса",
        "onboarding.button.next": "Дальше",
        "onboarding.button.skip": "Пропустить",
        "onboarding.deposit_option.popular_caps": "ПОПУЛЯРНО",
        "onboarding.page3.option1_title": "Попробовать",
        "onboarding.page3.option2_body": "≈ 10 откладываний · хватит на 2 недели",
        "onboarding.page3.option2_title": "Серьёзно",
        "onboarding.page3.option3_body": "≈ 20 откладываний · спокойный месяц",
        "onboarding.page3.option3_title": "Решительно",
        "onboarding.permissions.body": "Эти разрешения нужны, чтобы будильник прозвенел даже на беззвучном режиме.",
        "onboarding.permissions.caps": "ПОСЛЕДНИЙ ШАГ",
        "onboarding.permissions.grant_caps": "Дать",
        "onboarding.permissions.notifications_body": "Чтобы показать будильник на экране",
        "onboarding.permissions.notifications_title": "Уведомления",
        "onboarding.permissions.sound_body": "Чтобы таймеры не убивались системой",
        "onboarding.permissions.sound_title": "Фоновый режим",
        "onboarding.permissions.title": "Чтобы будильник работал",
        "onboarding.permissions.unavailable_caps": "Недоступно",
        "onboarding.splash.subtitle": "Будильник со ставкой"
    ]

    private static var allKeys: [String] {
        Array(copyBeforeMigration.keys) + ["onboarding.page3.option1_body"]
    }

    // MARK: - Layer 1: the catalogue says exactly what the code used to say

    func testMigratedCopyIsIdenticalToTheLiteralsItReplaced() {
        for (key, literal) in Self.copyBeforeMigration {
            XCTAssertEqual(
                Localized.text(key), literal,
                "«\(key)» no longer renders the text it replaced — the screen changed, which #600 forbids"
            )
        }
    }

    /// The smallest preset spells out the per-snooze price, so its catalogue
    /// entry carries a `%@` where the literal carried an interpolation. The
    /// amount is taken from `MoneyFormatter` rather than written as «50 ₽» so
    /// the test survives #559 changing the money format.
    func testFirstPresetKeepsTheAmountItInterpolates() {
        let price = MoneyFormatter.string(50)

        XCTAssertEqual(
            Localized.format("onboarding.page3.option1_body", price),
            "≈ 5 откладываний по \(price)"
        )
    }

    // MARK: - Layer 2a: the deposit page

    func testDepositPresetsComeFromTheCatalogue() {
        let controller = OnboardingViewController()

        let titles = controller.depositOptions.map(\.title)
        XCTAssertEqual(titles, [
            Localized.text("onboarding.page3.option1_title"),
            Localized.text("onboarding.page3.option2_title"),
            Localized.text("onboarding.page3.option3_title")
        ])

        let descriptions = controller.depositOptions.map(\.description)
        XCTAssertEqual(descriptions, [
            Localized.format("onboarding.page3.option1_body", MoneyFormatter.string(50)),
            Localized.text("onboarding.page3.option2_body"),
            Localized.text("onboarding.page3.option3_body")
        ])
    }

    /// The `ПОПУЛЯРНО` tag is drawn by `OnboardingDepositOptionView`, not by
    /// the VC, so a miss there is invisible in `depositOptions`.
    func testDepositPageRendersPresetCopyRatherThanKeys() {
        let controller = mount(OnboardingViewController())

        let rendered = controller.pageViews.flatMap { strings(in: $0) }
        assertNoKeysLeaked(in: rendered)

        for expected in [
            Localized.text("onboarding.page3.option1_title"),
            Localized.text("onboarding.page3.option2_title"),
            Localized.text("onboarding.page3.option3_title"),
            Localized.text("onboarding.deposit_option.popular_caps")
        ] {
            XCTAssertTrue(rendered.contains(expected), "the deposit page never renders «\(expected)»")
        }
    }

    /// `SnoozePayUITests/OnboardingFlowUITests` reaches these two by their
    /// text, so the catalogue values and the E2E expectations are one fact.
    ///
    /// The skip pill is a plain `UIButton` configured with an attributed
    /// title; `SPButton` hides its title in a private label and exposes the
    /// whole control as one accessibility element, which is also the string
    /// the UI test matches on.
    func testOnboardingChromeButtonsComeFromTheCatalogue() {
        let controller = mount(OnboardingViewController())

        let skip = controller.skipButton.configuration?.attributedTitle.map { String($0.characters) }
        XCTAssertEqual(skip, Localized.text("onboarding.button.skip"))
        XCTAssertEqual(controller.laterButton.accessibilityLabel, Localized.text("onboarding.button.later"))
    }

    // MARK: - Layer 2b: the permissions screen

    func testPermissionsScreenRendersCopyRatherThanKeys() {
        let controller = PermissionsViewController()
        controller.loadViewIfNeeded()

        let rendered = strings(in: controller.view)
        assertNoKeysLeaked(in: rendered)

        for expected in [
            Localized.text("onboarding.permissions.caps"),
            Localized.text("onboarding.permissions.title"),
            Localized.text("onboarding.permissions.body"),
            Localized.text("onboarding.permissions.notifications_title"),
            Localized.text("onboarding.permissions.notifications_body"),
            Localized.text("onboarding.permissions.sound_title"),
            Localized.text("onboarding.permissions.sound_body"),
            Localized.text("common.button.done")
        ] {
            XCTAssertTrue(rendered.contains(expected), "the permissions screen never renders «\(expected)»")
        }
    }

    /// The two caps affordances depend on runtime authorisation, so the states
    /// are applied directly instead of hoping the live screen lands on them.
    func testPermissionCardCapsAffordancesComeFromTheCatalogue() {
        let card = PermissionCardView(kind: .notifications)

        card.apply(status: .actionable)
        XCTAssertTrue(
            strings(in: card).contains(Localized.text("onboarding.permissions.grant_caps")),
            "an ungranted card lost its explicit grant affordance"
        )

        card.apply(status: .unavailable)
        XCTAssertTrue(
            strings(in: card).contains(Localized.text("onboarding.permissions.unavailable_caps")),
            "a card the user cannot act on lost its state caption"
        )
    }

    // MARK: - Layer 2c: the splash

    func testSplashRendersItsTaglineFromTheCatalogue() {
        let controller = SplashViewController()
        controller.loadViewIfNeeded()

        let rendered = strings(in: controller.view)
        assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(
            rendered.contains(Localized.text("onboarding.splash.subtitle")),
            "the splash never renders its tagline"
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

    /// Every piece of text the subtree renders — plain labels and attributed
    /// ones, since the caps captions and the skip pill are attributed.
    private func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }

    /// A key that reached the screen looks like `onboarding.permissions.title`.
    private func assertNoKeysLeaked(in rendered: [String], file: StaticString = #filePath, line: UInt = #line) {
        for key in Self.allKeys where rendered.contains(key) {
            XCTFail("«\(key)» rendered as its own key — the catalogue lookup missed", file: file, line: line)
        }
    }
}
