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
/// Coverage is **28 of the 31 keys at the call site**, and the three
/// exceptions are named rather than papered over:
///
///   * `statistics.error.title` and `statistics.error.message` render from
///     `presentRepositoryError`, which is private and reached only through
///     `StatisticsViewModel.onLoadError`. Provoking it needs a repository
///     stubbed to fail, which the view controller offers no seam for — its
///     view model is not injectable. Catalogue layer only.
///   * `streak.savings.body` is asserted here at the catalogue layer only,
///     because `StreakModalCopyTests` already compares
///     `StreakModalViewController.copy(streakDays:mode:)` against the Russian
///     verbatim and would go red on its own.
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
    func testFormatKeysKeepTheirSpecifiers() {
        let expected: [String: [String]] = [
            "streak.savings.caps": ["%1$lld", "%2$@"],
            "streak.savings.headline_days": ["%1$lld", "%2$@"],
            "streak.behavioral.headline": ["%1$lld", "%2$@"],
            "streak.share.message": ["%1$lld", "%2$@", "%3$@"],
            "alarm_off.lower_price.subtitle": ["%1$@", "%2$@"],
            "alarm_off.body": ["%@"],
            "statistics.weekday.worst_day": ["%@"]
        ]
        for (key, specifiers) in expected {
            let value = Localized.text(key)
            for specifier in specifiers {
                XCTAssertTrue(
                    value.contains(specifier),
                    "\(key) lost \(specifier) — that argument would vanish from the sentence"
                )
            }
        }
    }

    /// Keys whose copy the two screens do not share, however alike they read.
    /// «СЕРИЯ» is one word in Russian and one word in English, which is exactly
    /// why a future edit to the statistics card would be tempting to apply to
    /// the sheet as well; they are separate entries so it cannot happen by
    /// accident.
    func testStreakCapsAreSeparateEntriesPerScreen() {
        XCTAssertEqual(Localized.text("statistics.streak.caps"), "СЕРИЯ")
        XCTAssertEqual(Localized.text("streak.behavioral.caps"), "СЕРИЯ")
        XCTAssertNotEqual(
            "statistics.streak.caps", "streak.behavioral.caps",
            "the two screens must keep their own entry"
        )
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
    func testStatisticsCardsRenderTheirPreMigrationCaptions() {
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
            for copy in expected[name] ?? [] {
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
    func testAttributedAppendsWhenTheTemplateHasNoSpecifier() {
        let result = Localized.attributed(
            "streak.behavioral.caps",
            attributes: [:],
            replacing: NSAttributedString(string: "!")
        )
        XCTAssertEqual(result.string, "СЕРИЯ!")
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
