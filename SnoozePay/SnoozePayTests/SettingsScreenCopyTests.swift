import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy this slice of #600 moved out of the Settings screen itself —
/// `SettingsViewController`, its `+Referral` and `+Legal` extensions,
/// `ReferralRowCells` and `ThemeSegmentCell` — into `Localizable.xcstrings`.
///
/// `SettingsRowCopyTests` did the same for `+Sections.swift` (#718) and its
/// three-layer shape is kept deliberately, because the failure mode is the
/// same: a wrong key is silent. `Localized.text` hands the key back, the
/// header renders `settings.section.finance` where «ФИНАНСЫ» used to be, and
/// the build is green.
///
///  1. **Catalogue layer** — every key resolves to something other than itself.
///  2. **Copy layer** — every key still holds the exact words the screen
///     shipped, transcribed here from the pre-migration literals rather than
///     read back out of the catalogue, which would agree with any mistake in it.
///  3. **Call-site layer** — the real headers, rows and screens are built and
///     what they render is compared against the catalogue. Layers 1 and 2 are
///     blind to a typo in the *key* at the call site: there the catalogue is
///     fine and only the screen is wrong.
///
/// # What layer 3 does not reach in this slice
///
/// Five of the twenty-five keys are read only from code this suite does not
/// drive, and they are covered by layers 1 and 2 alone. The list is meant to
/// be exhaustive, because the next slice will read it as a checklist and an
/// incomplete one is worse than none:
///
///  * `settings.section.recovery` — the diagnostics header is rendered only
///    while `isRecoveryVisible` is true, and that reads
///    `AlarmRepository.shared.lastLoadFailed`. Not «no seam»:
///    `SettingsViewController` is not `final`, so a subclass could override
///    the property. That is substituting the object under test for one that
///    answers differently, which is a poor trade for a string assertion;
///  * `settings.no_mail.title` / `settings.no_mail.message` — assembled inside
///    the completion handler of `UIApplication.shared.open`, which runs only
///    on a host with no Mail client;
///  * `referral.error.apply_failed` — the `catch`-all in
///    `handleApplyFriendCodeTapped`, reached only when `applyFriendCode`
///    throws something that is not an `ApplyError`. The service is injected,
///    but as the concrete `ReferralService`, so there is nothing to substitute
///    a throwing double for;
///  * `common.button.ok` — its words are asserted here, but no call site of it
///    is. The key predates this slice; the one call site this slice gave it is
///    the no-mail alert above, and nothing else in the target drives it either.
///
/// «Not covered in this slice», not «unreachable»: extracting
/// `makeNoMailAlert() -> UIAlertController` would put the two alert strings in
/// reach with no host at all. That is a change to production structure, and
/// this slice moves strings only.
///
/// The two credited-bonus strings were on this list and are not any more: the
/// apply path needs no live balance, only the injected wallet that
/// `SettingsReferralIsolationTests` already uses, and
/// `testApplyingAFriendCodeShowsTheCreditedBonusCopy` drives it.
@MainActor
final class SettingsScreenCopyTests: XCTestCase {

    // MARK: - Fixtures torn down

    private var suites: [(name: String, defaults: UserDefaults)] = []
    private var hostWindows: [UIWindow] = []
    private var pasteboardNames: [UIPasteboard.Name] = []
    /// The table hands cells out without retaining them; hold them so the
    /// views under assertion outlive the call that built them.
    private var retainedCells: [UITableViewCell] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        retainedCells.removeAll()
        suites.forEach { $0.defaults.removePersistentDomain(forName: $0.name) }
        suites.removeAll()
        pasteboardNames.forEach { UIPasteboard.remove(withName: $0) }
        pasteboardNames.removeAll()
        super.tearDown()
    }

    // MARK: - Layers 1 + 2: the catalogue and its words

    /// The strings as they read on screen today, copied from the literals this
    /// slice replaced. `referral.button.apply` and `common.button.ok` are in
    /// the list although they predate it: this slice pointed two more call
    /// sites at them, so their words are now this screen's business too.
    private static let copy: [String: String] = [
        "common.button.ok": "Ок",
        "referral.button.apply": "Применить",
        "referral.error.apply_failed": "Не удалось применить код",
        "referral.hint.bonus_credited": "Бонус +%@ зачислен",
        "referral.row.already_applied": "Код уже применён",
        "referral.row.bonus_caption": "За каждого друга — +%@ на ваш баланс",
        "referral.row.friend_code_label": "Код друга",
        "referral.row.friend_code_placeholder": "Введите 6 символов",
        "referral.row.my_code": "Ваш код",
        "referral.toast.bonus_credited": "Бонус начислен",
        "referral.toast.copied": "Скопировано",
        "settings.legal.body": "%@\n\nДокумент будет добавлен перед публикацией в App Store.",
        "settings.no_mail.message": "Адрес поддержки %@ скопирован в буфер обмена.",
        "settings.no_mail.title": "Почта не настроена",
        "settings.section.finance": "ФИНАНСЫ",
        "settings.section.other": "ПРОЧЕЕ",
        "settings.section.recovery": "ВОССТАНОВЛЕНИЕ",
        "settings.section.referral": "ПРИГЛАСИТЬ ДРУГА",
        "settings.section.rules": "ПРАВИЛА",
        "settings.section.sound": "ЗВУК И УВЕДОМЛЕНИЯ",
        "settings.theme.dark": "Тёмная",
        "settings.theme.light": "Светлая",
        "settings.theme.system": "Системная",
        "settings.theme.title": "Тема",
        "settings.title": "Настройки"
    ]

    func testEveryKeyResolvesToCopyRatherThanToItself() {
        for key in Self.copy.keys {
            XCTAssertNotEqual(Localized.text(key), key, "missing catalogue key: \(key)")
        }
    }

    func testCatalogueStillHoldsTheWordsTheScreenShipped() {
        for (key, expected) in Self.copy {
            XCTAssertEqual(Localized.text(key), expected, "copy drifted for: \(key)")
        }
    }

    /// One `%@` each, no more: `Localized.format` spends a single argument per
    /// call here, so a template that grew a second specifier would render
    /// `%@` on screen rather than fail to build.
    func testEverySubstitutionTemplateCarriesExactlyOneSpecifier() {
        for key in [
            "referral.hint.bonus_credited",
            "referral.row.bonus_caption",
            "settings.legal.body",
            "settings.no_mail.message"
        ] {
            let template = Localized.text(key)
            XCTAssertEqual(
                template.components(separatedBy: "%@").count - 1, 1,
                "\(key) must hold exactly one %@ — it holds \(template)"
            )
        }
    }

    /// The theme row and the alarm's picture-theme picker both say «Тема» today
    /// and are deliberately two entries: one switches the app's appearance, the
    /// other picks a wallpaper for the firing screen. Only their separate
    /// existence is pinned — whether the words stay identical is a copy
    /// decision, and asserting equality would turn a legitimate divergence red.
    func testBothThemeTitlesHaveTheirOwnCatalogueEntry() {
        for key in ["settings.theme.title", "create_alarm.theme.title"] {
            XCTAssertNotEqual(Localized.text(key), key, "\(key) lost its own catalogue entry")
        }
    }

    // MARK: - Layer 3: the screen is wired to those keys

    func testScreenTitleComesFromTheCatalogue() {
        XCTAssertEqual(makeSUT().title, Localized.text("settings.title"))
    }

    func testSectionHeadersComeFromTheCatalogue() {
        let sut = makeSUT(referralEnabled: true)
        let expected: [(SettingsViewController.Section, String)] = [
            (.finance, "settings.section.finance"),
            (.soundNotifications, "settings.section.sound"),
            (.rules, "settings.section.rules"),
            (.referral, "settings.section.referral"),
            (.other, "settings.section.other")
        ]
        for (section, key) in expected {
            let title = sut.tableView(sut.tableView, titleForHeaderInSection: sut.sectionIndex(of: section))
            XCTAssertEqual(title, Localized.text(key), "header of \(section) is not wired to \(key)")
        }
    }

    /// The header view uppercases whatever it is handed, so a lowercase
    /// translation would still render in caps — but the words have to survive
    /// the trip through `viewForHeaderInSection` at all.
    func testTheRenderedHeaderShowsTheCatalogueWords() throws {
        let sut = makeSUT()
        let section = sut.sectionIndex(of: .finance)
        let header = try XCTUnwrap(sut.tableView(sut.tableView, viewForHeaderInSection: section))
        let rendered = Self.strings(in: header)

        XCTAssertTrue(
            rendered.contains(Localized.text("settings.section.finance").uppercased()),
            "the finance header renders \(rendered)"
        )
    }

    func testThemeRowRendersCatalogueCopy() {
        let sut = makeSUT()
        let indexPath = IndexPath(
            row: SettingsViewController.OtherRow.theme.rawValue,
            section: sut.sectionIndex(of: .other)
        )
        let rendered = Self.strings(in: retained(sut.cell(at: indexPath)))

        for key in ["settings.theme.title", "settings.theme.system", "settings.theme.light", "settings.theme.dark"] {
            XCTAssertTrue(rendered.contains(Localized.text(key)), "theme row renders \(rendered) — not \(key)")
        }
    }

    func testReferralRowsRenderCatalogueCopy() {
        let sut = makeSUT(referralEnabled: true)
        let section = sut.sectionIndex(of: .referral)

        assertRenders(["referral.row.my_code"], in: sut, at: IndexPath(row: 0, section: section))
        assertRenders(
            ["referral.row.friend_code_placeholder", "referral.button.apply"],
            in: sut,
            at: IndexPath(row: 1, section: section)
        )

        // `SPInput` paints its label in the caps role and uppercases whatever
        // it is handed, so the field renders «КОД ДРУГА» from a catalogue entry
        // that reads «Код друга». The rendered form is what to assert on
        // (#719); asserting the entry verbatim fails on copy that is correct.
        let field = Self.strings(in: retained(sut.cell(at: IndexPath(row: 1, section: section))))
        XCTAssertTrue(
            field.contains(Localized.text("referral.row.friend_code_label").uppercased()),
            "the friend-code field renders \(field) — not the copy of referral.row.friend_code_label"
        )

        let caption = Self.strings(in: retained(sut.cell(at: IndexPath(row: 2, section: section))))
        XCTAssertTrue(
            caption.contains(Localized.format("referral.row.bonus_caption", MoneyFormatter.string(200))),
            "the referral caption renders \(caption)"
        )
    }

    /// The hint on a frozen field is set from `configure(appliedCode:…)`, which
    /// the data source only reaches once a code has been redeemed. Configured
    /// directly so the branch is exercised without spending a real bonus.
    func testFrozenFriendCodeFieldShowsTheAppliedHint() {
        let sut = makeSUT(referralEnabled: true)
        let cell = ReferralFriendInputCell(style: .default, reuseIdentifier: ReferralFriendInputCell.reuseID)
        retainedCells.append(cell)

        cell.configure(appliedCode: "WAKE42", delegate: sut, onApply: {})

        XCTAssertEqual(cell.input.hint, Localized.text("referral.row.already_applied"))
    }

    func testLegalScreenRendersCatalogueBody() {
        let title = Localized.text("settings.row.privacy_policy")
        let legal = LegalViewController(title: title)
        legal.loadViewIfNeeded()

        let rendered = Self.strings(in: legal.view)
        XCTAssertTrue(
            rendered.contains(Localized.format("settings.legal.body", title)),
            "the legal placeholder renders \(rendered)"
        )
    }

    /// The toast is installed synchronously; only its fade is animated. Driven
    /// against an owned pasteboard for the reason `SettingsReferralIsolation
    /// Tests` spells out — `.general` is synced to the Mac's clipboard in the
    /// Simulator.
    func testCopyingTheCodeToastsWithCatalogueCopy() throws {
        let sut = hosted(makeSUT())
        let window = try XCTUnwrap(sut.view.window)

        sut.copyMyCodeToPasteboard(pasteboard: makePasteboard())

        let toast = try XCTUnwrap(
            Self.descendants(of: window).compactMap { $0 as? SettingsToastLabel }.first,
            "copying the code put no toast on the window"
        )
        XCTAssertEqual(toast.text, Localized.text("referral.toast.copied"))

        // The toast schedules its fade-out with `delay: 1.1`; left queued, it
        // is spent inside the first neighbouring test that waits on anything
        // (#618/#728). Paid for here instead.
        drainMainQueue()
    }

    /// The credited-bonus copy — the hint under the field and the toast — is
    /// the most-seen string in this slice: everyone who ever redeems a code
    /// reads it. No live balance is needed to drive it, only the injected
    /// wallet `SettingsReferralIsolationTests` already applies codes against.
    ///
    /// The captured `input` is the object the handler wrote to. The section
    /// reload that follows builds a *new* cell, configured from the now-applied
    /// code, whose hint is `referral.row.already_applied` — asserting on the
    /// row after the reload would measure the other string.
    func testApplyingAFriendCodeShowsTheCreditedBonusCopy() throws {
        // Own code fixed rather than generated, for the reason
        // `SettingsReferralIsolationTests` gives: `applyFriendCode` rejects a
        // self-apply, and a generated code could collide with the one applied.
        let fixture = makeFixture(referralEnabled: true, myCode: "ABCDEF")
        let sut = hosted(fixture.sut)
        let window = try XCTUnwrap(sut.view.window)

        // Dequeuing the row is what points `friendCodeInput` at a live cell.
        _ = retained(sut.cell(at: IndexPath(row: 1, section: sut.sectionIndex(of: .referral))))
        let input = try XCTUnwrap(sut.friendCodeInput)
        input.textField.text = "BCDEFG"

        sut.handleApplyFriendCodeTapped()

        XCTAssertNil(
            input.error,
            "the apply was rejected, so the assertions below would pass for the wrong reason"
        )
        // The amount in the copy is the amount credited, not a number this
        // test also hard-codes: the wallet is asked what it received.
        XCTAssertEqual(
            fixture.wallet.balance, ReferralService.referralBonusAmount,
            "the bonus did not land in the injected wallet"
        )
        XCTAssertEqual(
            input.hint,
            Localized.format("referral.hint.bonus_credited", MoneyFormatter.string(fixture.wallet.balance))
        )
        let toast = try XCTUnwrap(
            Self.descendants(of: window).compactMap { $0 as? SettingsToastLabel }.first,
            "the apply put no toast on the window"
        )
        XCTAssertEqual(toast.text, Localized.text("referral.toast.bonus_credited"))

        drainMainQueue()
    }

    // MARK: - Helpers

    /// Settings with every store it writes to pinned to a throwaway suite,
    /// plus the stores themselves for the tests that need to look inside.
    ///
    /// `getMyCode()` GENERATES and persists on first read, and `applyFriendCode`
    /// credits real money, so a shared `ReferralService` would write both into
    /// the test host's own defaults (#690).
    private struct Fixture {
        let sut: SettingsViewController
        /// The injected wallet, so a test can ask what the apply path actually
        /// credited instead of hard-coding the amount a second time.
        let wallet: BalanceService
    }

    /// `myCode` is spelled against the raw key rather than asked of the
    /// service, which keeps it `private` — the same choice, for the same
    /// reason, as `SettingsReferralIsolationTests`.
    private func makeFixture(
        referralEnabled: Bool = AppFeatureFlags.referralEnabled,
        myCode: String? = nil
    ) -> Fixture {
        let name = "test.settings.screencopy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        suites.append((name: name, defaults: defaults))
        if let myCode { defaults.set(myCode, forKey: "referral_my_code") }

        let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        let sut = SettingsViewController(
            alarmDefaults: AlarmDefaults(defaults: defaults),
            referralService: ReferralService(defaults: defaults, balanceService: wallet)
        )
        sut.referralEnabled = referralEnabled
        sut.loadViewIfNeeded()
        return Fixture(sut: sut, wallet: wallet)
    }

    private func makeSUT(referralEnabled: Bool = AppFeatureFlags.referralEnabled) -> SettingsViewController {
        makeFixture(referralEnabled: referralEnabled).sut
    }

    private func hosted(_ sut: SettingsViewController) -> SettingsViewController {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 900))
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = sut
        window.makeKeyAndVisible()
        hostWindows.append(window)
        window.layoutIfNeeded()
        return sut
    }

    private func makePasteboard() -> UIPasteboard {
        let pasteboard = UIPasteboard.withUniqueName()
        pasteboardNames.append(pasteboard.name)
        return pasteboard
    }

    private func retained(_ cell: UITableViewCell) -> UITableViewCell {
        retainedCells.append(cell)
        return cell
    }

    private func assertRenders(
        _ keys: [String],
        in sut: SettingsViewController,
        at indexPath: IndexPath,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rendered = Self.strings(in: retained(sut.cell(at: indexPath)))
        for key in keys {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "row \(indexPath) renders \(rendered) — not the copy of \(key)",
                file: file,
                line: line
            )
        }
    }

    /// Every string a view tree puts on screen. `UIButton` titles and
    /// `UITextField` placeholders are collected too — `SPSegmented` paints its
    /// options as button titles and `SPInput` its placeholder on the field, so
    /// a label-only walk would report the theme and referral rows as empty.
    private static func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        if let button = view as? UIButton {
            found.append(contentsOf: [button.currentTitle, button.currentAttributedTitle?.string].compactMap { $0 })
        }
        if let field = view as? UITextField {
            found.append(contentsOf: [field.text, field.placeholder].compactMap { $0 })
        }
        if let textView = view as? UITextView {
            found.append(contentsOf: [textView.text].compactMap { $0 })
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }

    private static func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}

private extension SettingsViewController {

    /// Section indices are POSITIONS in the live table, not raw values:
    /// `.referral` is hidden behind a flag (#676), so everything after it
    /// shifts up and a raw-value probe reads the wrong section in silence.
    func sectionIndex(of section: Section, file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let index = visibleSections.firstIndex(of: section) else {
            XCTFail("section \(section) is not visible; nothing to probe", file: file, line: line)
            return 0
        }
        return index
    }

    func cell(at indexPath: IndexPath) -> UITableViewCell {
        self.tableView(self.tableView, cellForRowAt: indexPath)
    }
}
