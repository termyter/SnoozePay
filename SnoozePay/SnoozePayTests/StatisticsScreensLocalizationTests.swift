import UIKit
import XCTest
@testable import SnoozePay

/// Guards the keys the Statistics screens moved into `Localizable.xcstrings`
/// (#600, part of #569): `StatisticsViewController`, its `+Cards` extension,
/// `StreakModalViewController` and `AlarmOffWarningViewController`.
///
/// The failure this exists for is the one nothing else can see. `Localized`
/// echoes a key it cannot find, so a typo — in the catalogue or at the call
/// site — turns the trend card's caption into `statistics.trend.caps` on
/// screen. It compiles, it does not log, it does not throw, and SwiftLint
/// cannot express it. Only an assertion notices.
///
/// # What these tests prove, and what they do not
///
/// Two layers, because they fail for different reasons and a red run should
/// name which:
///
///   * **Catalogue** — every key resolves to Russian copy rather than to
///     itself. Catches a deleted or renamed *entry*.
///   * **Call site** — the screens are built and their rendered strings
///     compared against the literals they held before the migration. This is
///     the layer that catches a renamed *usage*, which the catalogue layer
///     cannot: `Localized.text("alarm_off.capss")` leaves the catalogue
///     perfectly intact.
///
/// Coverage is **29 of 31 keys at the call site**; the two exceptions:
///
///   * `statistics.error.title` and `statistics.error.message` render from
///     `presentRepositoryError`. Catalogue layer only — **not for want of a
///     seam**, which is what this comment claimed until review. The seam is
///     three lines wide: `StatisticsViewController.viewModel` is internal,
///     `StatisticsViewModel.onLoadError` is internal, `bindViewModel()` runs
///     in `viewDidLoad`, so `loadViewIfNeeded()` →
///     `sut.viewModel.onLoadError?(error)` → read `presentedViewController`
///     needs no injection. Left uncovered because this slice moves strings,
///     not structure, and because the defect on that path — bare `catch`,
///     optional `onLoadError`, second alert dropped by the
///     `presentedViewController == nil` guard — is #721, which would rewrite
///     any test written against today's behaviour.
///
/// Both streak bodies are covered at the call site by `StreakModalCopyTests`.
/// Its behavioural test held only *negative* assertions until review — «no ₽»,
/// «no сэкономи» — which an echoed key satisfies too, so
/// `streak.behavioral.body` was the uncovered one and `streak.savings.body`
/// the covered one: backwards from what this comment used to say.
///
/// The rest of `StreakModalViewController` is deliberately **not** re-asserted
/// here. `StreakModalCopyTests` already pins `streakCaption`,
/// `savingsHeadline`, `shareText` and both `Copy` triples word for word, and
/// its rendered-sheet tests look up «Поделиться победой» and «Закрыть» in the
/// loaded view tree — so all 13 of that file's literals are covered at the
/// call site by a suite that predates this change. Duplicating it would add
/// maintenance, not coverage.
final class StatisticsScreensLocalizationTests: XCTestCase {

    // MARK: - Catalogue layer

    /// Every key this slice introduced, listed literally rather than derived
    /// from the catalogue — a loop over the file's own contents shrinks
    /// silently when an entry is deleted instead of failing.
    private static let migratedKeys = [
        "alarm_off.body",
        "alarm_off.button.dismiss",
        "alarm_off.caps",
        "alarm_off.disable.subtitle",
        "alarm_off.disable.title",
        "alarm_off.headline",
        "alarm_off.lower_price.subtitle",
        "alarm_off.lower_price.title",
        "alarm_off.reschedule.subtitle",
        "alarm_off.reschedule.title",
        "statistics.error.message",
        "statistics.error.title",
        "statistics.streak.caps",
        "statistics.title",
        "statistics.trend.axis_end",
        "statistics.trend.axis_start",
        "statistics.trend.caps",
        "statistics.trend.week_caption",
        "statistics.weekday.caps",
        "statistics.weekday.meta",
        "statistics.weekday.no_snoozes",
        "statistics.weekday.worst_day",
        "streak.behavioral.body",
        "streak.behavioral.caps",
        "streak.behavioral.headline",
        "streak.button.share",
        "streak.savings.body",
        "streak.savings.caps",
        "streak.savings.headline_days",
        "streak.savings.headline_week",
        "streak.share.message"
    ]

    func testEveryMigratedKeyResolvesToCopyRatherThanToItself() {
        for key in Self.migratedKeys {
            let value = Localized.text(key)
            XCTAssertNotEqual(
                value, key,
                "missing catalogue entry: \(key) — the UI would render the key itself"
            )
            XCTAssertFalse(value.isEmpty, "empty catalogue value for \(key)")
        }
    }

    func testEveryMigratedValueCarriesRussianText() {
        for key in Self.migratedKeys {
            let isCyrillic = Localized.text(key).unicodeScalars.contains {
                (0x0400...0x04FF).contains($0.value)
            }
            XCTAssertTrue(isCyrillic, "catalogue value for \(key) carries no Russian text")
        }
    }

    /// The part most easily lost in the trip through JSON: drop `%1$lld` while
    /// retyping and the sentence still reads perfectly, just without the
    /// number in it.
    ///
    /// Counted, not merely found: `Localized.attributed` spends its single
    /// replacement on the *first* occurrence of its specifier and renders any
    /// second one literally, so a duplicated specifier ships «списано −750 ₽ …
    /// %@» and `contains` alone never sees it.
    ///
    /// `create_alarm.snooze.minutes` joined the list with #722, which pointed
    /// `SnoozeSliderCell.valueText(_:)` at `Localized.attributed`: before
    /// that, the only reader of that entry was `String(format:)`, which had
    /// nothing to report about a second `%lld` — it reads one past the end of
    /// the argument list and prints whatever is there, which is undefined
    /// behaviour rather than an omission. It is spelled
    /// `%lld` rather than `%@` because of that older reader — the specifier is
    /// per entry, not a house style.
    ///
    /// The list is kept by hand, so it guards what is written in it and
    /// nothing else. Two things it structurally cannot see: a key whose call
    /// site was added without a line here, and a *translation* that grows a
    /// second specifier — `Localized.text` resolves for `AppLocale.display`,
    /// which is `Locale(identifier: "ru_RU")` until #569, so only the Russian
    /// template is ever counted.
    func testFormatKeysKeepTheirSpecifiers() {
        let expected: [String: [String]] = [
            "streak.savings.caps": ["%1$lld", "%2$@"],
            "streak.savings.headline_days": ["%1$lld", "%2$@"],
            "streak.behavioral.headline": ["%1$lld", "%2$@"],
            "streak.share.message": ["%1$lld", "%2$@", "%3$@"],
            "alarm_off.lower_price.subtitle": ["%1$@", "%2$@"],
            "alarm_off.body": ["%@"],
            "statistics.weekday.worst_day": ["%@"],
            "create_alarm.snooze.minutes": ["%lld"]
        ]
        for (key, specifiers) in expected {
            let value = Localized.text(key)
            for specifier in specifiers {
                XCTAssertEqual(
                    value.components(separatedBy: specifier).count - 1, 1,
                    "\(key) must hold exactly one \(specifier); it reads «\(value)»"
                )
            }
        }
    }

    /// Keys whose copy the two screens do not share, however alike they read.
    /// «СЕРИЯ» is one word in Russian and one word in English, which is exactly
    /// why a future edit to the statistics card would be tempting to apply to
    /// the sheet as well.
    ///
    /// What this pins is the *value* of each entry, not their separateness —
    /// that is held by `testEveryMigratedKeyResolvesToCopyRatherThanToItself`,
    /// since deleting either entry leaves the *deleted* key echoing itself —
    /// the survivor goes on resolving normally, which is why the survivor is
    /// not what the assertion is watching.
    /// An `XCTAssertNotEqual` between the two key *literals* stood here until
    /// review and proved nothing: two different string constants are unequal
    /// at compile time, catalogue or no catalogue.
    func testStreakCapsAreSeparateEntriesPerScreen() {
        XCTAssertEqual(Localized.text("statistics.streak.caps"), "СЕРИЯ")
        XCTAssertEqual(Localized.text("streak.behavioral.caps"), "СЕРИЯ")
    }

    // MARK: - Call site: AlarmOffWarningViewController

    /// Builds the sheet and reads back what it renders. Every string below is
    /// copied from the pre-migration source, so this fails both on a missing
    /// catalogue entry and on a call site pointed at the wrong key.
    func testAlarmOffWarningRendersItsPreMigrationCopy() {
        let sut = AlarmOffWarningViewController()
        sut.loadViewIfNeeded()
        let rendered = Self.renderedText(in: sut.view)

        let expected = [
            "Закрыть",
            "ВНИМАНИЕ",
            "Вы поспали ещё 3 раза подряд",
            "Перенести будильник",
            "Сегодня поздно лёг — встаём в 08:00",
            "Снизить цену откладывания",
            "Сейчас \(MoneyFormatter.string(50)) → попробовать \(MoneyFormatter.string(20))",
            "Выключить SnoozePay",
            "Будильник останется обычным",
            "Всё в порядке, продолжаем"
        ]
        for copy in expected {
            XCTAssertTrue(
                rendered.contains(copy),
                "«\(copy)» is not on the alarm-off sheet; rendered: \(rendered)"
            )
        }
    }

    /// The body was a prefix literal, an `append` and a suffix literal around
    /// the charged total; it is now one entry with the amount as `%@`.
    /// Asserting both ends *and* the amount between them is what proves the
    /// single key renders the whole sentence — a template that lost its
    /// specifier would still satisfy a `hasPrefix` check alone.
    func testAlarmOffWarningBodyKeepsTheAmountInsideOneSentence() throws {
        let sut = AlarmOffWarningViewController()
        sut.loadViewIfNeeded()

        let body = try XCTUnwrap(
            Self.renderedText(in: sut.view).first(where: { $0.hasPrefix("За эту неделю списано ") }),
            "body copy missing from the alarm-off sheet"
        )
        XCTAssertTrue(
            body.hasSuffix(". Возможно, что-то пошло не так. Что хотите сделать?"),
            "the sentence after the amount was lost: \(body)"
        )
        XCTAssertTrue(body.contains("750"), "the charged total is missing: \(body)")
    }

    // MARK: - Call site: StatisticsViewController + Cards

    /// The card builders are called directly, as `StatisticsFlameBadgeTests`
    /// does, rather than through a hosted screen: these captions are static
    /// copy, and going via `refresh()` would make the assertion depend on
    /// whatever the repository happens to hold.
    ///
    /// Expectations are unwrapped, not defaulted: `expected[name] ?? []` turns
    /// a renamed card into zero iterations and a green run that checked
    /// nothing.
    func testStatisticsCardsRenderTheirPreMigrationCaptions() throws {
        let sut = StatisticsViewController()

        let cases: [(String, [String])] = [
            ("hero", Self.renderedText(in: sut.makeHeroStreakCard())),
            ("weekday", Self.renderedText(in: sut.makeWeekdayCard())),
            ("trend", Self.renderedText(in: sut.makeTrendCard()))
        ]
        let expected: [String: [String]] = [
            "hero": ["СЕРИЯ"],
            "weekday": ["ПО ДНЯМ НЕДЕЛИ", "За последние 4 недели"],
            "trend": ["ДИНАМИКА ОТКЛАДЫВАНИЙ", "Эта неделя", "8 недель назад", "эта неделя"]
        ]
        for (name, rendered) in cases {
            let copies = try XCTUnwrap(expected[name], "no expectations declared for \(name)")
            for copy in copies {
                XCTAssertTrue(
                    rendered.contains(copy),
                    "«\(copy)» is not on the \(name) card; rendered: \(rendered)"
                )
            }
        }
    }

    /// The axis tick and the column heading differ only in the case of one
    /// letter, which is precisely how they would end up merged onto a single
    /// key by someone tidying the catalogue.
    func testTrendWeekCaptionAndAxisTickKeepTheirOwnCasing() {
        XCTAssertEqual(Localized.text("statistics.trend.week_caption"), "Эта неделя")
        XCTAssertEqual(Localized.text("statistics.trend.axis_end"), "эта неделя")
    }

    func testStatisticsScreenTitleComesFromTheCatalogue() {
        let sut = StatisticsViewController()
        sut.loadViewIfNeeded()

        XCTAssertEqual(sut.title, "Статистика")
        XCTAssertTrue(
            Self.renderedText(in: sut.view).contains("Статистика"),
            "the page header no longer renders the screen title"
        )
    }

    // MARK: - Call site: the weekday headline

    func testWeekdayHeadlineWithoutSnoozesIsUnchanged() {
        XCTAssertEqual(
            StatisticsViewController.weekdayHeadline(worstDayNames: []).string,
            "Откладываний не было"
        )
    }

    /// One entry with `%@` where the code held a prefix literal — the rendered
    /// sentence must come out identical anyway, and the day name must still
    /// carry its own tint rather than being flattened into the base run.
    func testWeekdayHeadlineSubstitutesTheDayAndKeepsItsTint() throws {
        let headline = StatisticsViewController.weekdayHeadline(worstDayNames: ["среда"])
        XCTAssertEqual(headline.string, "Чаще всего — среда")

        let dayRange = try XCTUnwrap(
            headline.string.range(of: "среда"),
            "the day name never made it into the headline"
        )
        let colour = headline.attribute(
            .foregroundColor,
            at: NSRange(dayRange, in: headline.string).location,
            effectiveRange: nil
        ) as? UIColor
        XCTAssertEqual(colour, StatisticsAccentTones.pain, "the worst day lost its tint")
    }

    func testWeekdayHeadlineJoinsTiedDays() {
        let headline = StatisticsViewController.weekdayHeadline(worstDayNames: ["среда", "пятница"])
        XCTAssertTrue(headline.string.hasPrefix("Чаще всего — "), headline.string)
        XCTAssertTrue(headline.string.contains("среда"), headline.string)
        XCTAssertTrue(headline.string.contains("пятница"), headline.string)
    }

    // MARK: - Localized.attributed

    func testAttributedKeepsEachSideOwnAttributes() {
        let replacement = NSAttributedString(
            string: "среда",
            attributes: [.foregroundColor: UIColor.red]
        )
        let result = Localized.attributed(
            "statistics.weekday.worst_day",
            attributes: [.foregroundColor: UIColor.green],
            replacing: replacement
        )
        XCTAssertEqual(result.string, "Чаще всего — среда")
        XCTAssertEqual(
            result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
            .green,
            "the surrounding sentence lost its own attributes"
        )
        XCTAssertEqual(
            result.attribute(.foregroundColor, at: result.length - 1, effectiveRange: nil) as? UIColor,
            .red,
            "the substituted run was flattened into the base attributes"
        )
    }

    /// A template without a specifier must not swallow the run. The amount
    /// landing in an odd place is recoverable by the reader; a sentence
    /// silently missing it reads as fact and is wrong.
    ///
    /// Asserted through the recovery itself rather than through
    /// `Localized.attributed`, exactly as `AppHairlineTests` asserts
    /// `degenerateWidth` instead of calling `width(for:)` with a zero scale:
    /// that branch now traps on purpose, so reaching it the front way would
    /// abort the suite rather than measure anything. A template with no `%@`
    /// is a catalogue defect and until review it was silent; what stays
    /// testable is the release-build floor.
    ///
    /// The template is a literal, not a real key: this test used
    /// `streak.behavioral.caps`, and giving that entry a specifier would have
    /// quietly changed the test's meaning instead of failing it.
    func testAppendingUnplaceableKeepsTheRunRatherThanDroppingIt() {
        let result = Localized.appendingUnplaceable(
            template: "СЕРИЯ",
            attributes: [:],
            replacement: NSAttributedString(string: "!")
        )
        XCTAssertEqual(result.string, "СЕРИЯ!")
    }

    /// The other half of that pair: no key the app actually passes to
    /// `Localized.attributed` may reach the trapping branch. Call sites are
    /// listed by symbol rather than by line — line numbers would go stale
    /// before the claim does, which in an epic whose whole defect is stale
    /// prose is a mine, not a convenience.
    ///
    /// There are three: `StatisticsViewController`'s worst-day caption,
    /// `AlarmOffWarningViewController`'s body, and — since #722 —
    /// `SnoozeSliderCell.valueText(_:)`. Avoiding line numbers did not save
    /// this list from going stale anyway: it read «the only two» until the
    /// third arrived and review caught it, which is the honest measure of what
    /// a hand-kept list is worth. A fourth added without a line here is still
    /// the gap this cannot see, and the trap inside `Localized.attributed` is
    /// what covers that case instead; that is the division of labour.
    ///
    /// The specifier travels with the key rather than being assumed `%@`:
    /// `create_alarm.snooze.minutes` holds `%lld`, and a loop hard-wired to
    /// `%@` would have quietly reported that entry as taking the trapping
    /// branch.
    func testAttributedSubstitutesInPlaceForEveryKeyTheAppPassesIt() {
        let callSites = [
            (key: "alarm_off.body", specifier: "%@"),
            (key: "statistics.weekday.worst_day", specifier: "%@"),
            (key: "create_alarm.snooze.minutes", specifier: "%lld")
        ]
        for (key, specifier) in callSites {
            let template = Localized.text(key)
            XCTAssertTrue(
                template.contains(specifier),
                "\(key) would take the trapping branch: it reads «\(template)»"
            )
            let result = Localized.attributed(
                key,
                attributes: [:],
                replacing: NSAttributedString(string: "X"),
                specifier: specifier
            )
            XCTAssertEqual(
                result.string,
                template.replacingOccurrences(of: specifier, with: "X"),
                "\(key) did not substitute in place"
            )
        }
    }

    // MARK: - Helpers

    /// Every user-visible string in the tree: label text plus the
    /// accessibility label `SPButton` derives from its title. Mirrors the
    /// helper in `StreakModalCopyTests`; `attributedText` is read too, because
    /// the alarm-off caps and body set only that.
    private static func renderedText(in view: UIView) -> [String] {
        var found: [String] = []
        for subview in view.subviews {
            if let label = subview as? UILabel {
                if let text = label.text { found.append(text) }
                // `UILabel` synthesises `attributedText` from `text`, so this
                // only adds anything for the labels that set the attributed
                // form directly — the alarm-off caps and body.
                if let attributed = label.attributedText, attributed.string != label.text {
                    found.append(attributed.string)
                }
            }
            if let button = subview as? SPButton, let title = button.accessibilityLabel {
                found.append(title)
            }
            found.append(contentsOf: renderedText(in: subview))
        }
        return found
    }
}
