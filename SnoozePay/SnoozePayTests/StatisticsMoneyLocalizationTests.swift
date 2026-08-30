import XCTest
@testable import SnoozePay

/// Guards the keys `StatisticsViewModel+Money` moved into
/// `Localizable.xcstrings` (#599, part of #569).
///
/// Same failure mode `ViewModelLocalizationTests` was written for: `Localized`
/// echoes a missing key, so a typo turns the state column into
/// `statistics.savings.no_price` on screen without anything throwing, logging
/// or failing to compile.
///
/// Two kinds of assertion, and the split is deliberate:
///
///   * The **copy** assertions below spell the Russian sentence out as a Swift
///     literal, copied from the pre-migration version of the file. Comparing
///     `Localized.text(k)` with `Localized.text(k)` would be green whatever the
///     catalogue said; comparing the call site with the words it used to return
///     is what actually proves the migration lossless — including that the two
///     ledger failures did not swap keys, which the older
///     `StatisticsDataHealthTests` check (non-empty and distinct) allows.
///   * The **specifier** assertions guard the part most easily lost in the trip
///     through JSON: drop `%1$lld` while retyping and the sentence still reads
///     perfectly, just without the number in it.
///
/// The wake-time captions are not re-asserted here — `StatisticsWakeTimeTests`
/// already compares them against the Russian verbatim, so post-migration it
/// covers the whole chain (call site → key → catalogue → copy) unchanged.
final class StatisticsMoneyLocalizationTests: XCTestCase {

    /// Every key this slice introduced. Listed literally rather than derived
    /// from the catalogue, so deleting an entry fails instead of shrinking the
    /// loop.
    private static let migratedKeys = [
        "statistics.ledger_unavailable.partial",
        "statistics.ledger_unavailable.unreadable",
        "statistics.savings.alarms_unreadable",
        "statistics.savings.free_alarms",
        "statistics.savings.no_price",
        "statistics.wake_time.delta_earlier",
        "statistics.wake_time.delta_later",
        "statistics.wake_time.delta_unchanged",
        "statistics.wake_time.delta_value",
        "statistics.wake_time.samples_pending"
    ]

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

    func testMigratedCopyIsTheRussianSourceText() {
        for key in Self.migratedKeys {
            let isCyrillic = Localized.text(key).unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
            XCTAssertTrue(isCyrillic, "catalogue value for \(key) carries no Russian text")
        }
    }

    // MARK: - The call sites still return the pre-migration words

    func testLedgerUnavailableMessagesAreUnchanged() {
        XCTAssertEqual(
            StatisticsViewModel.LedgerUnavailableReason.ledgerUnreadable.message,
            "Не удалось прочитать историю списаний — данные за неделю скрыты"
        )
        // One catalogue entry now, where the code concatenated two halves —
        // the rendered sentence must come out identical anyway.
        XCTAssertEqual(
            StatisticsViewModel.LedgerUnavailableReason.ledgerPartiallyRead.message,
            "История списаний прочитана не полностью — данные за неделю скрыты, "
                + "чтобы не показать заниженные суммы"
        )
    }

    func testSnoozePriceExplanationsAreUnchanged() {
        XCTAssertEqual(
            StatisticsViewModel.SnoozePriceState.noPricedAlarms.explanation,
            "Сэкономленное появится, когда у будильника будет цена снуза"
        )
        XCTAssertEqual(
            StatisticsViewModel.SnoozePriceState.alarmStoreUnreadable.explanation,
            "Не удалось прочитать будильники — сэкономленное не посчитать"
        )
        XCTAssertNil(
            StatisticsViewModel.SnoozePriceState.known(50).explanation,
            "A resolved price owes the user no explanation"
        )
    }

    // MARK: - Substitutions survived the move into JSON

    func testWakeTimeFormatKeysKeepTheirSpecifiers() {
        XCTAssertTrue(
            Localized.text("statistics.wake_time.delta_value").contains("%lld"),
            "the minute count would vanish from «34 мин»"
        )
        let pending = Localized.text("statistics.wake_time.samples_pending")
        XCTAssertTrue(pending.contains("%1$lld"), "the morning count would vanish")
        XCTAssertTrue(pending.contains("%2$@"), "the declined noun would vanish")
    }

    /// `%lld` and `Int` have to agree: a `%@` in the catalogue would print a
    /// pointer, and `String(format:)` gives no warning about it.
    func testMinuteCountSubstitutesAsANumber() {
        XCTAssertEqual(StatisticsViewModel.wakeDeltaValueText(minutes: -34), "34 мин")
    }
}
