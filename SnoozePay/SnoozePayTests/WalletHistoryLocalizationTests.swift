import XCTest
@testable import SnoozePay

/// Guards the keys `TxHistoryPeriod` and `WalletTransactionPreview` moved into
/// `Localizable.xcstrings` (#599, part of #569), plus the one decision that
/// migration had to make: which month names are copy and which are calendar
/// data.
///
/// The behavioural assertions on the migrated call sites are NOT duplicated
/// here — `TxHistoryPeriodTests` and `WalletTransactionPreviewTests` already
/// compare against the Russian words verbatim («январь 2026», «3 мес.»,
/// «Сегодня · HH:mm»), and #599 left them untouched on purpose: unchanged,
/// they now assert the whole chain (call site → key → catalogue → copy)
/// instead of just its tail. What lives here is what those cannot see — that a
/// key exists at all, that its specifier survived the trip into JSON, and that
/// the CLDR facts the month split rests on are still true.
final class WalletHistoryLocalizationTests: XCTestCase {

    /// Every key #599 introduced for this slice. Listed literally rather than
    /// derived from the catalogue, so deleting an entry fails instead of
    /// shrinking the loop.
    private static let migratedKeys =
        ["wallet.history.filter.all",
         "wallet.history.filter.charges",
         "wallet.history.filter.credits",
         "wallet.history.timestamp.date",
         "wallet.history.timestamp.today",
         "wallet.history.timestamp.yesterday",
         "wallet.period.month_count"]
        + (1...12).map { String(format: "wallet.month.short_%02d", $0) }

    /// The Russian month abbreviations as they stood in `TxHistoryPeriod`
    /// before the move — written out here as Swift literals, not read back
    /// out of the catalogue, so that this asserts the migration rather than
    /// asserting the catalogue against itself.
    private static let shortMonthCopy =
        ["янв", "фев", "мар", "апр", "май", "июн",
         "июл", "авг", "сен", "окт", "ноя", "дек"]

    private static let fullMonthCopy =
        ["январь", "февраль", "март", "апрель", "май", "июнь",
         "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try XCTUnwrap(calendar.date(from: components))
    }

    // MARK: - The keys resolve

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

    /// `wallet.history.timestamp.date` is excluded deliberately: it is two
    /// substitutions and a separator («%1$@ · %2$@»), with no word of its own.
    func testMigratedCopyIsTheRussianSourceText() {
        for key in Self.migratedKeys where key != "wallet.history.timestamp.date" {
            let isCyrillic = Localized.text(key).unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
            XCTAssertTrue(isCyrillic, "catalogue value for \(key) carries no Russian text")
        }
    }

    // MARK: - Substitutions survived the move into JSON

    /// Drop `%@` while retyping the copy and nothing throws — the timestamp
    /// simply loses its clock, and the month counter its number.
    func testFormatKeysKeepTheirSubstitutionSpecifiers() {
        XCTAssertTrue(Localized.text("wallet.history.timestamp.today").contains("%@"))
        XCTAssertTrue(Localized.text("wallet.history.timestamp.yesterday").contains("%@"))
        XCTAssertTrue(Localized.text("wallet.history.timestamp.date").contains("%1$@"))
        XCTAssertTrue(Localized.text("wallet.history.timestamp.date").contains("%2$@"))
        XCTAssertTrue(Localized.text("wallet.period.month_count").contains("%lld"))
    }

    func testMonthCounterSubstitutesItsNumber() {
        let period = TxHistoryPeriod(
            start: YearMonth(year: 2025, month: 11),
            end: YearMonth(year: 2026, month: 10)
        )
        XCTAssertEqual(period.monthCountText, "12 мес.")
    }

    func testFilterChipTitlesComeFromTheCatalogue() {
        XCTAssertEqual(TxHistoryTypeFilter.allCases.map(\.title), ["Все", "Списания", "Поступления"])
    }

    func testTransactionTitlesComeFromTheCatalogue() {
        // `.unknown` carries the token the ledger actually held — a row a
        // newer build wrote, which this one still has to render.
        let types: [TransactionType] = [.charge, .topup, .promotion, .refund, .unknown("cashback")]
        let titles = types.map { type in
            WalletTransactionPreview.item(
                for: Transaction(type: type, amount: 50, createdAt: Date())
            ).title
        }
        XCTAssertEqual(
            titles,
            ["Поспать ещё", "Пополнение баланса", "Бонус за друга", "Возврат за откладывание", "Операция"]
        )
    }

    // MARK: - Month names: half calendar data, half copy

    /// Full names now come from `standaloneMonthSymbols`, and the swap is only
    /// safe because Foundation's Russian symbols are the previous hand-written
    /// array character for character. That is an assumption about CLDR, not
    /// about this code, so it is asserted rather than trusted — a future OS
    /// that reshapes the symbols should name itself here instead of reddening
    /// a dozen unrelated period-chip tests.
    func testFullMonthNamesAreTheDesignCopyInNominativeCase() {
        XCTAssertEqual(YearMonth.fullNames, Self.fullMonthCopy)
    }

    /// The other half of the same decision: the abbreviations are NOT taken
    /// from the calendar, and this is why. `ru_RU` ships «янв., февр., март,
    /// …» — trailing periods, four months not abbreviated at all, widths from
    /// three to five characters. Should CLDR ever converge on the three-letter
    /// tokens the design uses, this failing test is the invitation to delete
    /// the twelve catalogue keys.
    func testAbbreviatedMonthNamesDifferFromTheCalendarSymbols() throws {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.display
        let system = try XCTUnwrap(formatter.shortStandaloneMonthSymbols)
        XCTAssertEqual(system.first, "янв.", "CLDR abbreviations moved — recheck the copy/data split")
        XCTAssertNotEqual(
            YearMonth.shortNames, system,
            "the calendar now matches the design tokens — wallet.month.short_* can go"
        )
    }

    func testAbbreviatedMonthNamesAreTheDesignCopy() {
        XCTAssertEqual(YearMonth.shortNames, Self.shortMonthCopy)
    }

    func testMonthCaptionsRenderTheSameStringsAsBefore() {
        let january = YearMonth(year: 2026, month: 1)
        XCTAssertEqual(january.fullCaption, "январь 2026")
        XCTAssertEqual(january.shortCaption, "янв 2026")
        XCTAssertEqual(january.capitalizedCaption, "Январь 2026")
        XCTAssertEqual(january.capitalizedShortCaption, "Янв 2026")
        XCTAssertEqual(january.gridLabel, "Янв")
    }

    // MARK: - Date format stayed behaviour rather than becoming copy

    /// `timestampText` moved from the literal pattern `"d MMM"` to a localized
    /// template. Under `ru_RU` the template resolves to the same pattern, so
    /// the rendered date must not have moved — and the month must stay in the
    /// abbreviation the pattern produces («12 янв.»), which is a different set
    /// of symbols from the «янв» token of the period chips.
    func testOlderTimestampIsUnchangedByTheTemplateSwitch() throws {
        let older = try date(year: 2026, month: 1, day: 12, hour: 9, minute: 0)
        let now = try date(year: 2026, month: 1, day: 20, hour: 8, minute: 0)
        XCTAssertEqual(
            WalletTransactionPreview.timestampText(for: older, now: now, calendar: calendar),
            "12 янв. · 09:00"
        )
    }

    func testTodayAndYesterdayTimestampsKeepTheirSeparator() throws {
        let now = try date(year: 2026, month: 1, day: 20, hour: 8, minute: 0)
        let yesterday = try date(year: 2026, month: 1, day: 19, hour: 21, minute: 32)
        XCTAssertEqual(
            WalletTransactionPreview.timestampText(for: now, now: now, calendar: calendar),
            "Сегодня · 08:00"
        )
        XCTAssertEqual(
            WalletTransactionPreview.timestampText(for: yesterday, now: now, calendar: calendar),
            "Вчера · 21:32"
        )
    }
}
