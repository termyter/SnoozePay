import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that slice 3 of #612 moved out of `ViewControllers/Wallet`
/// into `Localizable.xcstrings`.
///
/// A wrong key is silent here: `Localized.text` hands back the key itself, the
/// wallet renders `wallet.footer.disclaimer` under its balance, and the build
/// ships. So, like `DesignSystemCopyTests`, the checks come in three layers and
/// a red run names which one broke:
///
///  1. **Catalogue layer** — every key exists.
///  2. **Copy layer** — every key still holds the exact words it held before
///     the migration. The expected values are typed out from the pre-migration
///     literals rather than read back from the file under test, which is what
///     makes the PR's «nothing moved on screen» claim checkable.
///  3. **Call-site layer** — the real screens are built and what they render is
///     compared against the catalogue. Layers 1 and 2 are both blind to a typo
///     in the *key* at the call site, because there the catalogue is fine.
final class WalletCopyTests: XCTestCase {

    // MARK: - Layer 1 + 2: the catalogue and its words

    private static let copy: [String: String] = [
        "common.balance_corrupted.title": "Баланс повреждён",
        "common.button.cancel": "Отмена",
        "common.button.later": "Позже",
        "common.button.ok": "Ок",
        "common.button.reset": "Сбросить",
        "common.button.top_up": "Пополнить",
        "common.purchase_failed.message": "Попробуйте ещё раз.",
        "common.purchase_failed.title": "Покупка не выполнена",
        "deposit.balance_corrupted.message":
            "Сохранённый баланс некорректен. Пополнение недоступно, "
            + "пока вы не сбросите баланс в ноль.",
        "deposit.button.restore": "Восстановить покупки",
        "deposit.disclaimer": "Деньги попадают в баланс. Списываются только при откладывании.",
        "deposit.error.products_unavailable":
            "Не удалось загрузить пакеты пополнения. Попробуйте позже.",
        "deposit.preset.snooze_count": "≈ %1$lld %2$@",
        "deposit.success.caption": "Зачислено на баланс",
        "deposit.title": "Пополнить баланс",
        "wallet.balance_corrupted.message":
            "Сохранённый баланс некорректен и был сброшен в ноль. "
            + "Пополнения временно недоступны, пока вы не подтвердите сброс.",
        "wallet.chart.caps": "ПОСЛЕДНИЕ 7 ДНЕЙ",
        "wallet.footer.disclaimer": "Покупка не возвращается · списывается только при откладывании",
        "wallet.hint.empty_balance": "Пока баланс пуст — пополните, чтобы откладывать",
        "wallet.history.caps": "ИСТОРИЯ ОПЕРАЦИЙ",
        "wallet.history.day.today": "Сегодня",
        "wallet.history.day.yesterday": "Вчера",
        "wallet.history.empty": "Здесь появятся пополнения, списания и бонусы.",
        "wallet.history.empty_period": "За выбранный период операций нет.",
        "wallet.history.empty_period_type": "За выбранный период таких операций нет.",
        "wallet.history.link_all": "Все операции →",
        "wallet.history.load_failed": "Не удалось загрузить историю",
        "wallet.history.period.accessibility": "Период: %@",
        "wallet.history.summary.caps": "За %@",
        "wallet.history.summary.snoozes": "Откладываний",
        "wallet.history.summary.spent": "Списано",
        "wallet.history.summary.topups": "Пополнения",
        "wallet.history.title": "История",
        "wallet.history.unrecognized_notice":
            "Часть операций не распознана — итоги ниже могут быть неполными",
        "wallet.period.button.apply": "Применить",
        "wallet.period.button.reset": "Сбросить",
        "wallet.period.empty": "Выберите месяц",
        "wallet.period.title": "Период",
        "wallet.title": "Кошелёк",
        "wallet.tx.charge": "Поспать ещё",
        "wallet.tx.promotion": "Бонус за друга",
        "wallet.tx.refund": "Возврат за откладывание",
        "wallet.tx.topup": "Пополнение баланса",
        "wallet.tx.unknown": "Операция"
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

    // MARK: - Layer 3: the wallet tab

    func testWalletTabRendersItsChromeRatherThanKeys() {
        let wallet = WalletViewController()
        wallet.loadViewIfNeeded()

        let rendered = Self.strings(in: wallet.view)
        assertNoKeysLeaked(Self.allKeys, in: rendered)
        for key in [
            "wallet.title", "common.button.top_up", "wallet.chart.caps",
            "wallet.history.caps", "wallet.history.link_all", "wallet.footer.disclaimer"
        ] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the wallet tab never renders «\(Localized.text(key))»"
            )
        }
    }

    /// The two preview cards say opposite things — «nothing happened yet» vs.
    /// «your history could not be read» (#419) — and swapping their keys is
    /// exactly the mistake the migration could make while still compiling.
    func testWalletPreviewEmptyAndErrorCardsKeepTheirOppositeCopy() {
        let wallet = WalletViewController()

        let empty = Self.strings(in: wallet.makeTxPreviewCard(items: []))
        XCTAssertTrue(empty.contains(Localized.text("wallet.history.empty")))
        XCTAssertFalse(
            empty.contains(Localized.text("wallet.history.load_failed")),
            "the empty preview card now claims the ledger failed to load"
        )

        let failed = Self.strings(in: wallet.makeTxPreviewErrorCard())
        XCTAssertTrue(failed.contains(Localized.text("wallet.history.load_failed")))
        XCTAssertFalse(
            failed.contains(Localized.text("wallet.history.empty")),
            "a corrupt ledger now reads as the friendly empty state"
        )
    }

    /// Seven Cyrillic initials that are no longer typed out: they are the first
    /// letters of the locale's own standalone weekday symbols. Whichever day
    /// today is, the seven-day window covers every weekday exactly once.
    func testWeeklyChartInitialsStillReadAsTheHandWrittenSet() {
        let chart = WalletWeeklyChartView()

        XCTAssertEqual(
            chart.dayLabels.sorted(),
            ["В", "В", "П", "П", "С", "С", "Ч"].sorted(),
            "the chart's weekday initials drifted off the design copy"
        )
    }

    // MARK: - Layer 3: the deposit sheet

    func testDepositSheetRendersItsFormRatherThanKeys() {
        let sheet = DepositBottomSheetViewController()
        sheet.loadViewIfNeeded()

        let rendered = Self.strings(in: sheet.view)
        assertNoKeysLeaked(Self.allKeys, in: rendered)
        for key in [
            "deposit.title", "deposit.disclaimer", "deposit.button.restore",
            "deposit.success.caption", "common.button.top_up"
        ] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the deposit sheet never renders «\(Localized.text(key))»"
            )
        }
    }

    /// The one two-argument string in this slice: a swapped pair reads
    /// «≈ откладываний 3» and still compiles. The declension itself stays with
    /// `Plural`, which `PluralTests` cross-checks against the other six call
    /// sites — this only pins the order.
    func testPresetHintKeepsTheCountBeforeItsNoun() throws {
        let label = DepositPresets.snoozeCountLabel(forAmount: 149)
        let noun = DepositPresets.snoozeNoun(for: 3)

        let count = try XCTUnwrap(label.range(of: "3"), "the count never reached the label: \(label)")
        let word = try XCTUnwrap(label.range(of: noun), "the noun never reached the label: \(label)")
        XCTAssertLessThan(count.lowerBound, word.lowerBound, "count must precede its noun: \(label)")
        XCTAssertEqual(label, "≈ 3 откладывания", "the preset hint drifted off its pre-migration text")
    }

    // MARK: - Layer 3: the period picker

    func testPeriodPickerRendersItsChromeRatherThanKeys() {
        let picker = PeriodPickerSheetViewController(selected: nil, years: [2026]) { _ in }
        picker.loadViewIfNeeded()

        let rendered = Self.strings(in: picker.view)
        assertNoKeysLeaked(Self.allKeys, in: rendered)
        for key in [
            "wallet.period.title", "wallet.period.button.reset",
            "wallet.period.button.apply", "wallet.period.empty"
        ] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the period picker never renders «\(Localized.text(key))»"
            )
        }
    }

    // MARK: - Layer 3: the transaction history

    func testHistoryScreenRendersItsChromeRatherThanKeys() {
        let history = WalletTransactionHistoryViewController()
        history.loadViewIfNeeded()

        XCTAssertEqual(history.title, Localized.text("wallet.history.title"))

        let rendered = Self.strings(in: history.view)
        assertNoKeysLeaked(Self.allKeys, in: rendered)
        for key in [
            "wallet.history.summary.spent", "wallet.history.summary.topups",
            "wallet.history.summary.snoozes"
        ] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the history screen never renders «\(Localized.text(key))»"
            )
        }
    }

    /// Both the chip's VoiceOver label and the summary caption substitute the
    /// period into a sentence, and both were assembled by interpolation before
    /// the migration. The screen opens on the current month, so the expected
    /// strings are computable rather than fixed.
    func testHistoryPeriodCaptionsSubstituteTheSelectedPeriod() {
        let history = WalletTransactionHistoryViewController()
        history.loadViewIfNeeded()
        let period = TxHistoryPeriod.currentMonth()

        let rendered = Self.strings(in: history.view)
        XCTAssertTrue(
            rendered.contains(
                Localized.format("wallet.history.period.accessibility", period.chipCaption)
            ),
            "the period chip lost its VoiceOver caption: \(rendered)"
        )
        XCTAssertTrue(
            rendered.contains(
                Localized.format("wallet.history.summary.caps", period.summaryCaption)
                    .uppercased(with: AppLocale.display)
            ),
            "the summary card lost its period caption: \(rendered)"
        )
    }

    /// Three different empty states live one `if` apart, which is the shape a
    /// copy-pasted key survives. `empty_period_type` needs a type chip other
    /// than «Все», which is private state — it stays pinned by layer 2.
    func testHistoryEmptyStatesUseTheirOwnCopy() {
        let history = WalletTransactionHistoryViewController()

        let untouched = Self.strings(in: history.makeEmptyCard(
            hasAnyTransactions: false, periodHasTransactions: false
        ))
        XCTAssertTrue(untouched.contains(Localized.text("wallet.history.empty")))

        let emptyPeriod = Self.strings(in: history.makeEmptyCard(
            hasAnyTransactions: true, periodHasTransactions: false
        ))
        XCTAssertTrue(emptyPeriod.contains(Localized.text("wallet.history.empty_period")))
        XCTAssertFalse(
            emptyPeriod.contains(Localized.text("wallet.history.empty")),
            "an empty period now reads as an untouched ledger"
        )

        let unreadable = Self.strings(in: history.makeLoadErrorCard())
        XCTAssertTrue(unreadable.contains(Localized.text("wallet.history.load_failed")))

        let partial = Self.strings(in: history.makeUnrecognizedRowsNotice())
        XCTAssertTrue(partial.contains(Localized.text("wallet.history.unrecognized_notice")))
    }

    /// Five row titles switched over in one `switch`; an off-by-one there is
    /// invisible until a user sees «Бонус за друга» on a snooze charge.
    func testTransactionRowTitlesComeFromTheCatalogue() {
        let expected: [TransactionType: String] = [
            .topup: "wallet.tx.topup",
            .charge: "wallet.tx.charge",
            .promotion: "wallet.tx.promotion",
            .refund: "wallet.tx.refund",
            .unknown("future"): "wallet.tx.unknown"
        ]
        for (type, key) in expected {
            let transaction = Transaction(type: type, amount: 50)
            XCTAssertEqual(
                WalletTransactionHistoryViewController.title(for: transaction),
                Localized.text(key),
                "row title for \(type.rawValue) no longer reads \(key)"
            )
        }
    }

    // MARK: - Layer 3: the hint on the balance card

    func testEmptyBalanceHintComesFromTheCatalogue() {
        XCTAssertEqual(WalletHints.emptyBalanceHint, Localized.text("wallet.hint.empty_balance"))
        XCTAssertEqual(
            WalletHints.affordHint(forBalance: 0, alarms: []),
            Localized.text("wallet.hint.empty_balance"),
            "a zero balance stopped routing to the wallet-specific hint"
        )
    }

    // MARK: - Helpers

    /// Every piece of text a subtree renders — plain labels, attributed labels
    /// (the caps captions are attributed), button titles built from a
    /// `UIButton.Configuration`, and the accessibility labels controls expose
    /// instead of a reachable title label.
    private static func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        if let button = view as? UIButton {
            found.append(contentsOf: [button.currentTitle].compactMap { $0 })
            if let title = button.configuration?.attributedTitle {
                found.append(String(title.characters))
            }
        }
        if let control = view as? UIControl, let label = control.accessibilityLabel {
            found.append(label)
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }
}
