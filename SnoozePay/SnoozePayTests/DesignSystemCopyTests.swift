import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that #601 moved out of `Views/DesignSystem` into
/// `Localizable.xcstrings`.
///
/// The design-system components are the half of the migration a screen test
/// cannot reach: `SPBalanceCard`, `SPSnoozePrice` and friends build their own
/// labels in property initialisers, so a wrong key never reaches a view
/// controller to be noticed there. And a wrong key is silent — `Localized.text`
/// hands back the key, `SPStatsEmptyState` renders `statistics.empty.title`,
/// and the build ships.
///
/// So the tests come in three layers, and a red run names which one broke:
///
///  1. **Catalogue layer** — every key exists.
///  2. **Copy layer** — every key still holds the exact words it held before
///     the migration. This is the layer that makes the PR's claim of "no
///     visible change" checkable rather than asserted; layer 1 passes just as
///     happily against a catalogue whose values were retyped from memory.
///  3. **Call-site layer** — the real views are built and what they render is
///     compared against the catalogue. Layer 1 and 2 are both blind to a typo
///     in the *key* at the call site, because the catalogue is fine in that
///     case.
final class DesignSystemCopyTests: XCTestCase {

    // MARK: - Layer 1 + 2: the catalogue and its words

    /// Written out rather than read back from the catalogue: a list derived
    /// from the file under test agrees with any mistake in it. These are the
    /// strings as they read on screen today, copied from the pre-migration
    /// literals.
    private static let copy: [String: String] = [
        "alarms.empty.body": "Создайте первый — выставите время, цену откладывания и положите баланс.",
        "alarms.empty.button": "Создать будильник",
        "alarms.empty.title": "Ни одного будильника",
        "alarms.title": "Будильники",
        "common.button.top_up": "Пополнить",
        "common.caps.balance": "БАЛАНС",
        "common.switch.accessibility": "Переключатель",
        "deposit.preset.popular": "Популярно",
        "firing.snooze.accessibility": "Отложить на %lld минут",
        "firing.snooze.caps": "Спать ещё %lld мин",
        "firing.ticker.caps": "СЕГОДНЯ",
        "statistics.empty.body": "Статистика появится после первой недели использования.",
        "statistics.empty.streak_chip": "Серия · %1$lld %2$@",
        "statistics.empty.title": "Пока нечего считать",
        "statistics.empty.unavailable_title": "Статистика недоступна",
        "statistics.wake_time.average": "В среднем",
        "statistics.wake_time.baseline": "Раньше было",
        "statistics.wake_time.caps": "ВРЕМЯ ПОДЪЁМА",
        "statistics.wake_time.pending": "Сравнение появится, когда наберётся история",
        "statistics.week.caps": "ЭТА НЕДЕЛЯ",
        "statistics.week.empty": "За эту неделю данных пока нет",
        "statistics.week.legend": "зелёное — сэкономлено · красное — потеряно",
        "statistics.week.net": "Чистый",
        "statistics.week.saved": "Сэкономили",
        "statistics.week.spent": "Потратили",
        "wallet.balance.delta_week": "%1$@ %2$@ за неделю"
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

    // MARK: - Layer 3: the alarms list chrome

    func testAlarmsListHeaderRendersCopyRatherThanKeys() {
        let header = SPAlarmsListHeader(frame: CGRect(x: 0, y: 0, width: 402, height: 220))
        header.setBalance(500, hint: nil)
        header.layoutIfNeeded()

        let rendered = Self.strings(in: header)
        Self.assertNoKeysLeaked(in: rendered)
        for key in ["alarms.title", "common.caps.balance", "common.button.top_up"] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the alarms header never renders «\(Localized.text(key))»"
            )
        }
    }

    func testAlarmsEmptyStateRendersCopyRatherThanKeys() {
        let empty = SPAlarmsListEmptyState(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        empty.layoutIfNeeded()

        let rendered = Self.strings(in: empty)
        Self.assertNoKeysLeaked(in: rendered)
        for key in ["alarms.empty.title", "alarms.empty.body", "alarms.empty.button"] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the alarms empty state never renders «\(Localized.text(key))»"
            )
        }
    }

    // MARK: - Layer 3: the statistics cards

    func testStatisticsCardsRenderCopyRatherThanKeys() {
        let week = SPWeekMoneyCard()
        let wake = SPWakeTimeCard()
        week.layoutIfNeeded()
        wake.layoutIfNeeded()

        let rendered = Self.strings(in: week) + Self.strings(in: wake)
        Self.assertNoKeysLeaked(in: rendered)
        for key in [
            "statistics.week.caps", "statistics.week.empty", "statistics.week.legend",
            "statistics.week.saved", "statistics.week.spent", "statistics.week.net",
            "statistics.wake_time.caps", "statistics.wake_time.average",
            "statistics.wake_time.baseline", "statistics.wake_time.pending"
        ] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "the statistics cards never render «\(Localized.text(key))»"
            )
        }
    }

    /// `setUnavailable` and `restoreEmptyAppearance` write the same two labels
    /// from three different keys, which is exactly the shape that survives a
    /// copy-paste of the wrong key.
    func testStatsEmptyStateSwapsBetweenAvailableAndUnavailableCopy() {
        let state = SPStatsEmptyState(frame: CGRect(x: 0, y: 0, width: 402, height: 400))

        state.setStreak(0)
        var rendered = Self.strings(in: state)
        XCTAssertTrue(rendered.contains(Localized.text("statistics.empty.title")))
        XCTAssertTrue(rendered.contains(Localized.text("statistics.empty.body")))

        state.setUnavailable("Историю прочитать не удалось")
        rendered = Self.strings(in: state)
        XCTAssertTrue(rendered.contains(Localized.text("statistics.empty.unavailable_title")))
        XCTAssertFalse(
            rendered.contains(Localized.text("statistics.empty.title")),
            "the unavailable state still shows the plain empty headline"
        )

        state.setStreak(3)
        rendered = Self.strings(in: state)
        XCTAssertTrue(
            rendered.contains(Localized.text("statistics.empty.title")),
            "setStreak did not restore the empty-state headline"
        )
        Self.assertNoKeysLeaked(in: rendered)
    }

    /// The streak chip is the one two-argument string in this slice, so a
    /// swapped pair would read «Серия · дня 2» and still compile.
    func testStreakChipKeepsTheCountBeforeItsNoun() throws {
        let days = 3
        let word = StreakModalViewController.dayWord(for: days)
        let chip = Localized.format("statistics.empty.streak_chip", days, word)

        let count = try XCTUnwrap(chip.range(of: "\(days)"), "the day count never reached the chip: \(chip)")
        let noun = try XCTUnwrap(chip.range(of: word), "the declined noun never reached the chip: \(chip)")
        XCTAssertLessThan(count.lowerBound, noun.lowerBound, "count must precede its noun: \(chip)")
    }

    // MARK: - Layer 3: the firing chrome

    func testSnoozePriceRendersItsMinutesInBothCapsAndVoiceOver() {
        let control = SPSnoozePrice(price: 50, minutes: 7)
        control.layoutIfNeeded()

        XCTAssertEqual(control.accessibilityLabel, Localized.format("firing.snooze.accessibility", 7))
        // Substring rather than equality: the caps line starts with a clock
        // glyph carried as an `NSTextAttachment`, so `attributedText.string`
        // is `U+FFFC` + two spaces + the words.
        let caps = Localized.format("firing.snooze.caps", 7).uppercased()
        XCTAssertTrue(
            Self.strings(in: control).contains(where: { $0.hasSuffix(caps) }),
            "the caps line lost its minutes: \(Self.strings(in: control))"
        )
    }

    func testFiringTickerKeepsItsEyebrow() {
        let row = SPFiringTicker.makeRow(for: [SPFiringTicker.Entry(amount: 50)])
        row.layoutIfNeeded()

        let rendered = Self.strings(in: row)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("firing.ticker.caps")))
    }

    // MARK: - Layer 3: the wallet chrome

    /// The delta line substitutes two arguments in a row, and both are opaque
    /// `%@` — so a swapped pair reads «120 ₽ ↓ за неделю» and looks plausible.
    func testBalanceCardDeltaKeepsTheArrowBeforeTheAmount() throws {
        let card = SPBalanceCard(balance: 500, delta: -120)
        card.layoutIfNeeded()

        let delta = try XCTUnwrap(
            Self.strings(in: card).first { $0.contains("за неделю") },
            "the balance card never rendered a weekly delta: \(Self.strings(in: card))"
        )
        let arrow = try XCTUnwrap(delta.range(of: "↓"), "the down arrow is missing: \(delta)")
        let amount = try XCTUnwrap(delta.range(of: "120"), "the amount is missing: \(delta)")
        XCTAssertLessThan(arrow.lowerBound, amount.lowerBound, "arrow must precede the amount: \(delta)")
    }

    func testAmountPresetBadgeAndSwitchLabelComeFromTheCatalogue() {
        let preset = SPAmountPreset(value: 500, popular: true)
        preset.layoutIfNeeded()

        let rendered = Self.strings(in: preset)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("deposit.preset.popular")))
        XCTAssertEqual(SPSwitch().accessibilityLabel, Localized.text("common.switch.accessibility"))
    }

    // MARK: - Helpers

    /// Every piece of text the subtree renders — plain labels, attributed
    /// labels (the caps captions are attributed) and the accessibility labels
    /// the controls expose instead of a reachable title label.
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

    /// A key that reached the screen looks like `statistics.week.caps`.
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
