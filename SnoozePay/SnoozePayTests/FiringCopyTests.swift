import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that #612 moved off the firing screen and into
/// `Localizable.xcstrings`.
///
/// This is the screen where a silent miss costs the most: it appears while the
/// user is half asleep, it is the only place that spends their money, and
/// `Localized.text` hands back the key on a miss — so a mistyped key ships as
/// `firing.no_balance.body` printed under the clock and the build stays green.
///
/// Three layers, so a red run names which one broke:
///
///  1. **Catalogue layer** — every key exists.
///  2. **Copy layer** — every key still holds the exact words it held before
///     the migration, transcribed from the pre-migration literals rather than
///     read back out of the file under test. A list derived from the catalogue
///     would agree with any mistake in it.
///  3. **Call-site layer** — the real screens are built and what they render is
///     compared against the catalogue. Layers 1 and 2 are both blind to a typo
///     in the *key* at the call site, because there the catalogue is fine.
///
/// The entries that take arguments get their own tests: word order is what a
/// two-key sentence throws away, so «+2 откладывания» and «Удержались после 2
/// откладываний» are asserted whole, not as «contains the number».
final class FiringCopyTests: XCTestCase {

    // MARK: - Layer 1 + 2: the catalogue and its words

    private static let copy: [String: String] = [
        "common.button.close": "Закрыть",
        "common.button.ok": "Ок",
        "common.button.top_up": "Пополнить",
        "firing.alert.purchase_failed.message": "Попробуйте ещё раз.",
        "firing.alert.purchase_failed.title": "Покупка не выполнена",
        "firing.alert.refund_failed.message":
            "%@ Будильник не зазвенит повторно, а вернуть деньги автоматически не вышло. "
            + "Напишите в поддержку — спишем вручную.",
        "firing.alert.refund_failed.title": "Не удалось вернуть списание",
        "firing.alert.snooze_not_scheduled.message":
            "%@ Будильник не зазвенит повторно — установите запасной. "
            + "Списанные деньги возвращены на баланс.",
        "firing.alert.snooze_not_scheduled.title": "Откладывание не запланировано",
        "firing.audio.config_failed": "Звук недоступен — другое приложение использует аудио. Проверьте режим звука.",
        "firing.audio.vibration_only": "Звук не воспроизводится — будильник вибрирует.",
        "firing.button.dismiss": "Я встал — выключить",
        "firing.eyebrow.get_up_only": "Только встать",
        "firing.eyebrow.wake_up": "Пора вставать",
        "firing.hint.max_price": "максимум — дальше только встать",
        "firing.hint.next_price": "следующее откладывание: %@",
        "firing.no_balance.body": "Откладывать больше не получится. Только встать.",
        "firing.no_balance.choose_amount": "Выбрать другую сумму",
        "firing.no_balance.hint": "Недостаточно средств",
        "firing.no_balance.pill": "Баланса не осталось",
        "firing.pill.balance": "Баланс",
        "firing.progressive.pill": "Прогрессив · %lld-й поспать ещё",
        "firing.top_up.footer": "Зачислится мгновенно. Откладывание будет доступно сразу.",
        "firing.top_up.load_failed": "Не удалось загрузить пакеты пополнения. Попробуйте позже.",
        "firing.top_up.pause": "Будильник на паузе · %@",
        "firing.top_up.row.hint.missing": "не хватает %@",
        "firing.top_up.row.hint.price": "по %@ за откладывание",
        "firing.top_up.row.title.generic": "Пополнить баланс",
        "firing.top_up.row.title.insufficient": "Не хватит на откладывание",
        "firing.top_up.row.title.snoozes": "+%1$lld %2$@",
        "firing.top_up.subtitle.insufficient":
            "Откладывание сейчас стоит %1$@. Даже %2$@ на него не хватит — "
            + "понадобится несколько пополнений.",
        "firing.top_up.subtitle.no_price":
            "Самое маленькое пополнение — %@. Можно больше, чтобы не возвращаться сюда.",
        "firing.top_up.subtitle.smallest":
            "Откладывание сейчас стоит %1$@. Хватит самого маленького пополнения — %2$@. "
            + "Можно больше, чтобы не возвращаться сюда.",
        "firing.top_up.subtitle.threshold":
            "Откладывание сейчас стоит %1$@. Хватит начиная с %2$@ — "
            + "меньшие пополнения откладывание не разблокируют.",
        "firing.top_up.success": "Возвращаем к будильнику через 2 секунды",
        "firing.top_up.title": "Пополнить баланс",
        "woke_morning.eyebrow": "Доброе утро",
        "woke_morning.headline.clean": "Встал с первого раза",
        "woke_morning.headline.recovered": "Удержались после %1$lld %2$@",
        "woke_morning.headline.unavailable": "Вы встали",
        "woke_morning.headline.unchanged": "Баланс не изменился",
        "woke_morning.subtitle.clean": "Баланс в полной сохранности. Так держать.",
        "woke_morning.subtitle.recovered": "Сегодня списано %lld ₽. Завтра попробуем не списать ничего.",
        "woke_morning.subtitle.reversed_charged":
            "Сегодня списано %1$lld ₽. Не состоявшихся откладываний: %2$lld — "
            + "деньги за них вернули.",
        "woke_morning.subtitle.reversed_none":
            "Списаний не осталось. Не состоявшихся откладываний: %lld — деньги за них вернули.",
        "woke_morning.subtitle.unavailable":
            "Историю списаний прочитать не удалось, поэтому сумму за это утро мы не "
            + "показываем. Текущий баланс — на главном экране."
    ]

    private static var allKeys: [String] { copy.keys.sorted() }

    func testEveryMigratedKeyResolvesToCopy() {
        for key in Self.allKeys {
            XCTAssertNotNil(Localized.optionalText(key), "missing catalogue key: \(key)")
            XCTAssertNotEqual(
                Localized.text(key), key,
                "\(key) resolves to itself — the entry is absent or holds the key as its value"
            )
        }
    }

    func testMigratedCopyStillReadsTheWayItDidBefore() {
        for (key, expected) in Self.copy {
            XCTAssertEqual(Localized.text(key), expected, "copy drifted for \(key)")
        }
    }

    // MARK: - Layer 3: the firing screen

    func testFiringScreenRendersCopyRatherThanKeys() {
        let firing = hostedFiring(balance: 1000)
        let rendered = Self.strings(in: firing.view)
        Self.assertNoKeysLeaked(in: rendered)

        XCTAssertTrue(
            rendered.contains(Localized.text("firing.button.dismiss")),
            "the firing screen never renders «\(Localized.text("firing.button.dismiss"))»: \(rendered)"
        )
        // The eyebrow and the balance pill are transformed at the call site —
        // the caps face is presentation, the catalogue holds the sentence — so
        // they are matched inside the rendered run rather than against it.
        XCTAssertTrue(
            rendered.contains { $0.contains(Localized.text("firing.eyebrow.wake_up").uppercased()) },
            "the solvent screen never renders the «пора вставать» eyebrow: \(rendered)"
        )
        XCTAssertTrue(
            rendered.contains { $0.hasPrefix(Localized.text("firing.pill.balance")) },
            "the balance pill lost its label segment: \(rendered)"
        )
    }

    func testFiringNoBalanceStateRendersCopyRatherThanKeys() {
        let firing = hostedFiring(balance: 0)
        let rendered = Self.strings(in: firing.view)
        Self.assertNoKeysLeaked(in: rendered)

        for key in [
            "firing.no_balance.pill",
            "firing.no_balance.body",
            "firing.no_balance.hint",
            "firing.no_balance.choose_amount",
            "common.button.top_up"
        ] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the no-balance state never renders «\(Localized.text(key))»: \(rendered)"
            )
        }
        XCTAssertTrue(
            rendered.contains { $0.contains(Localized.text("firing.eyebrow.get_up_only").uppercased()) },
            "the drained screen kept the solvent eyebrow: \(rendered)"
        )
    }

    // The snooze-cost hint keeps its own suite: `AlarmFiringHintTests` asserts
    // both branches whole, and now does so against the catalogue.

    // MARK: - Layer 3: the WokeMorning summary

    func testWokeMorningScreenRendersCopyRatherThanKeys() {
        let content = WokeMorningContent(snoozes: 2, charged: 150)
        let summary = WokeMorningViewController(content: content, onClose: {})
        summary.loadViewIfNeeded()
        summary.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        summary.view.layoutIfNeeded()

        let rendered = Self.strings(in: summary.view)
        Self.assertNoKeysLeaked(in: rendered)
        for expected in [
            WokeMorningContent.eyebrow,
            content.headline,
            content.subtitle,
            Localized.text("common.button.close")
        ] {
            XCTAssertTrue(
                rendered.contains(expected),
                "the summary never renders «\(expected)»: \(rendered)"
            )
        }
    }

    // MARK: - Layer 3: the firing-time top-up sheet

    func testTopUpSheetRendersCopyRatherThanKeys() {
        let sheet = FiringTopUpBottomSheetViewController(snoozePrice: 200, currentBalance: 0)
        sheet.loadViewIfNeeded()
        sheet.view.frame = CGRect(x: 0, y: 0, width: 402, height: 600)
        sheet.view.layoutIfNeeded()

        let rendered = Self.strings(in: sheet.view)
        Self.assertNoKeysLeaked(in: rendered)
        for key in ["firing.top_up.title", "firing.top_up.footer", "firing.top_up.success"] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the top-up sheet never renders «\(Localized.text(key))»: \(rendered)"
            )
        }
        XCTAssertTrue(
            rendered.contains(
                FiringTopUpCopy.subtitle(
                    amounts: FiringTopUpBottomSheetViewController.defaultPresets.map(\.amount),
                    balance: 0,
                    price: 200
                )
            ),
            "the sheet subtitle is no longer the one FiringTopUpCopy computes: \(rendered)"
        )
    }

    // MARK: - The entries that take arguments

    /// «+2 откладывания» — the count leads in Russian and does not in English,
    /// which is the whole reason the pair is one entry and not two.
    func testTopUpRowTitleKeepsTheCountAndTheNounInOneString() {
        // The argument-free branches are asserted by `FiringTopUpCopyTests`.
        XCTAssertEqual(
            FiringTopUpCopy.rowTitle(topUp: 500, balance: 0, price: 200),
            "+2 \(SnoozeAffordability.snoozeWord(for: 2))"
        )
    }

    /// All four subtitle branches are one entry each — a translator gets the
    /// price sentence and the advice sentence together, and can reorder them.
    func testTopUpSubtitleKeepsBothSentencesInOneEntry() {
        let price = MoneyFormatter.string(200)
        XCTAssertEqual(
            FiringTopUpCopy.subtitle(amounts: [149, 499], balance: 0, price: 0),
            "Самое маленькое пополнение — \(MoneyFormatter.string(149)). "
            + "Можно больше, чтобы не возвращаться сюда."
        )
        XCTAssertEqual(
            FiringTopUpCopy.subtitle(amounts: [49, 99], balance: 0, price: 200),
            "Откладывание сейчас стоит \(price). Даже \(MoneyFormatter.string(99)) "
            + "на него не хватит — понадобится несколько пополнений."
        )
        XCTAssertEqual(
            FiringTopUpCopy.subtitle(amounts: [499, 999], balance: 0, price: 200),
            "Откладывание сейчас стоит \(price). Хватит самого маленького пополнения — "
            + "\(MoneyFormatter.string(499)). Можно больше, чтобы не возвращаться сюда."
        )
        XCTAssertEqual(
            FiringTopUpCopy.subtitle(amounts: [149, 499], balance: 0, price: 200),
            "Откладывание сейчас стоит \(price). Хватит начиная с "
            + "\(MoneyFormatter.string(499)) — меньшие пополнения откладывание не разблокируют."
        )
    }

    func testProgressivePillCountsUpThroughTheCatalogue() {
        XCTAssertEqual(
            AlarmFiringViewController.progressivePillText(snoozeCount: 0),
            "Прогрессив · 1-й поспать ещё"
        )
        XCTAssertEqual(
            AlarmFiringViewController.progressivePillText(snoozeCount: 2),
            "Прогрессив · 3-й поспать ещё"
        )
    }

    func testWokeMorningPhrasesKeepTheirNumbersInPlace() {
        XCTAssertEqual(
            WokeMorningContent(snoozes: 2, charged: 100).headline,
            "Удержались после 2 \(WokeMorningContent.snoozeWord(for: 2))"
        )
        XCTAssertEqual(
            WokeMorningContent(snoozes: 2, charged: 100).subtitle,
            "Сегодня списано 100 ₽. Завтра попробуем не списать ничего."
        )
        XCTAssertEqual(
            WokeMorningContent(snoozes: 1, charged: 50, attempts: 3).subtitle,
            "Сегодня списано 50 ₽. Не состоявшихся откладываний: 2 — деньги за них вернули."
        )
        XCTAssertEqual(
            WokeMorningContent(snoozes: 0, charged: 0, attempts: 2).subtitle,
            "Списаний не осталось. Не состоявшихся откладываний: 2 — деньги за них вернули."
        )
    }

    /// Asserting the composed string is what catches a specifier that vanished
    /// from an entry — `String(format:)` drops the argument without complaint.
    func testSubstitutionsActuallySubstitute() {
        XCTAssertEqual(
            Localized.format("firing.top_up.pause", "00:54"),
            "Будильник на паузе · 00:54"
        )
        XCTAssertEqual(
            Localized.format("firing.hint.next_price", MoneyFormatter.string(100)),
            "следующее откладывание: \(MoneyFormatter.string(100))"
        )
        XCTAssertTrue(
            Localized.format("firing.alert.snooze_not_scheduled.message", "Причина.")
                .hasPrefix("Причина. Будильник не зазвенит повторно"),
            "the scheduler's reason no longer opens the alert body"
        )
        XCTAssertTrue(
            Localized.format("firing.alert.refund_failed.message", "Причина.")
                .hasPrefix("Причина. Будильник не зазвенит повторно"),
            "the scheduler's reason no longer opens the refund-failure body"
        )
    }

    // MARK: - Harness

    /// Windows are retained for the test's lifetime: a `UIWindow` nothing holds
    /// can deallocate mid-assertion and take the hierarchy — and every string in
    /// it — with it.
    private var hostWindows: [UIWindow] = []
    private var hostControllers: [AlarmFiringViewController] = []

    override func tearDown() {
        // `viewDidLoad` starts the alarm sound; `viewDidDisappear` stops it.
        hostControllers.forEach { $0.viewDidDisappear(false) }
        AudioService.shared.stopAlarmSound()
        hostWindows.forEach { $0.rootViewController = nil }
        hostControllers = []
        hostWindows = []
        super.tearDown()
    }

    private func hostedFiring(balance: Double) -> AlarmFiringViewController {
        let viewModel = AlarmFiringViewModel(
            alarm: Alarm(name: "Работа", snoozeMinutes: 5, penaltyAmount: 50),
            snoozeCount: 0,
            snoozeAnchor: nil,
            balanceService: FiringCopyWallet(balance: balance)
        )
        let firing = AlarmFiringViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = firing
        hostWindows.append(window)
        hostControllers.append(firing)

        firing.loadViewIfNeeded()
        firing.viewDidAppear(false)
        firing.view.frame = window.bounds
        window.setNeedsLayout()
        window.layoutIfNeeded()
        firing.view.layoutIfNeeded()

        // A detached hierarchy lays out at `.zero` and renders nothing.
        XCTAssertFalse(firing.view.bounds.isEmpty, "the firing screen never laid out")
        return firing
    }

    /// Every piece of text the subtree renders — plain labels, attributed labels
    /// (the caps rows are attributed) and the accessibility labels the controls
    /// expose instead of a reachable title label.
    private static func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        if let control = view as? UIControl, let label = control.accessibilityLabel {
            found.append(label)
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }

    /// A key that reached the screen looks like `firing.no_balance.body`.
    private static func assertNoKeysLeaked(
        in rendered: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for key in allKeys where rendered.contains(key) {
            XCTFail("«\(key)» rendered as its own key — the catalogue lookup missed", file: file, line: line)
        }
    }
}

// MARK: - Test doubles

/// Wallet stub — `canSnooze` is the single switch between the solvent screen
/// and the no-balance state, and it reads nothing but `canAfford`.
private final class FiringCopyWallet: AlarmFiringBalancing {
    var balance: Double

    init(balance: Double) {
        self.balance = balance
    }

    func canAfford(_ amount: Double) -> Bool { balance >= amount }

    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        balance -= amount
        return Transaction(type: .charge, amount: amount, alarmID: alarmID?.uuidString)
    }

    @discardableResult
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool {
        balance += amount
        return true
    }
}
