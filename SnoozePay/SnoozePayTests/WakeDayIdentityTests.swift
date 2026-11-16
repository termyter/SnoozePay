import XCTest
@testable import SnoozePay

/// Coverage for ``WakeDayIdentity`` and the cross-timezone defect #1064
/// describes: a morning recorded in one zone used to disappear from the
/// streak, the heatmap and the savings counter once the device reported a
/// different zone.
///
/// The oracle is the issue's own example: wake at 07:00 Europe/Moscow on
/// 2026-10-25 (04:00Z). A raw `startOfDay` record is 2026-10-24 21:00Z, while
/// the same visible morning rebuilt under Asia/Dubai is 2026-10-24 20:00Z —
/// instant equality fails, identity equality must not.
final class WakeDayIdentityTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WakeDayIdentityTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func calendar(_ zone: String, mondayFirst: Bool = false) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        if mondayFirst { cal.firstWeekday = 2 }
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
        in cal: Calendar
    ) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Identity of a walked day

    func testWalkedDayIdentityIsZoneIndependent() {
        let moscow = calendar("Europe/Moscow")
        let dubai = calendar("Asia/Dubai")

        let moscowMidnight = date(2026, 10, 25, in: moscow)
        let dubaiMidnight = date(2026, 10, 25, in: dubai)

        // Same civil day, two different instants (21:00Z vs 20:00Z).
        XCTAssertNotEqual(moscowMidnight, dubaiMidnight)
        XCTAssertEqual(
            WakeDayIdentity(date: moscowMidnight, calendar: moscow),
            WakeDayIdentity(date: dubaiMidnight, calendar: dubai),
            "The same visible calendar day must have one identity everywhere"
        )
    }

    func testConsecutiveDaysHaveDistinctOrderedIdentities() {
        let calendar = self.calendar("UTC")
        let first = WakeDayIdentity(date: date(2026, 10, 24, in: calendar), calendar: calendar)
        let second = WakeDayIdentity(date: date(2026, 10, 25, in: calendar), calendar: calendar)

        XCTAssertLessThan(first, second)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.description, "2026-10-25")
    }

    // MARK: - Stored representations

    func testCanonicalStoredDayRoundTrips() {
        let identity = WakeDayIdentity(year: 2026, month: 10, day: 25)
        guard let stored = identity.canonicalStoredDay else {
            return XCTFail("A valid civil day must have a canonical storage value")
        }

        // Canonical form is the civil day's UTC midnight, by construction.
        let utc = calendar("UTC")
        let components = utc.dateComponents([.year, .month, .day, .hour, .minute], from: stored)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 25)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(WakeDayIdentity(storedDay: stored), identity)
    }

    func testLegacyStoredMidnightReconstructsTheCivilDayItWasWrittenFor() {
        // Raw `startOfDay` values from installs that predate #1064.
        let moscowStore = date(2026, 10, 24, 21, 0, in: calendar("UTC"))  // 00:00 +03
        let newYorkStore = date(2026, 10, 25, 4, 0, in: calendar("UTC"))  // 00:00 −04
        let kathmanduStore = date(2026, 10, 24, 18, 15, in: calendar("UTC")) // 00:00 +05:45

        let expected = WakeDayIdentity(year: 2026, month: 10, day: 25)
        XCTAssertEqual(WakeDayIdentity(storedDay: moscowStore), expected)
        XCTAssertEqual(WakeDayIdentity(storedDay: newYorkStore), expected)
        XCTAssertEqual(WakeDayIdentity(storedDay: kathmanduStore), expected)
    }

    func testLegacyAmbiguousWindowResolvesEastAsDocumented() {
        // A stored midnight near 10:00–12:00 UTC fits both the western
        // (−10…−12) and the eastern (+10…+14) offset. The documented rule
        // resolves east, which is the correct label for a UTC+14 write
        // (00:00 on 2026-10-25 is 2026-10-24 10:00Z).
        let lineIslandsStore = date(2026, 10, 24, 10, 0, in: calendar("UTC"))

        XCTAssertEqual(
            WakeDayIdentity(storedDay: lineIslandsStore),
            WakeDayIdentity(year: 2026, month: 10, day: 25)
        )
    }

    func testStoredIdentityIsNotTheReaderZoneFlooring() {
        // The stored value is a Moscow/Europe morning (20:00Z of the day
        // before, i.e. 00:00 +04). Re-flooring that instant in New York would
        // invent 2026-10-24 — the westbound defect #1064 warns about. The
        // identity must stay on the civil day the row was written for.
        let stored = date(2026, 10, 24, 20, 0, in: calendar("UTC"))
        let newYork = calendar("America/New_York")

        XCTAssertEqual(
            WakeDayIdentity(date: stored, calendar: newYork),
            WakeDayIdentity(year: 2026, month: 10, day: 24),
            "Reader-zone flooring does invent a previous day — the reason it is not used"
        )
        XCTAssertEqual(
            WakeDayIdentity(storedDay: stored),
            WakeDayIdentity(year: 2026, month: 10, day: 25)
        )
    }

    // MARK: - WakeEventStore writes canonical days

    func testRecordWakeStoresCanonicalDayNotStartOfDay() {
        let moscow = calendar("Europe/Moscow")
        let store = WakeEventStore(defaults: defaults)
        let wakeInstant = date(2026, 10, 25, 7, 0, in: moscow)

        store.recordWake(on: wakeInstant, calendar: moscow)

        let expectedCanonical = date(2026, 10, 25, in: calendar("UTC"))
        XCTAssertEqual(
            store.wakeDays(), [expectedCanonical],
            "New rows must carry the zone-free identity, not a local midnight"
        )
        XCTAssertEqual(store.wakeTimes(), [wakeInstant], "Raw history is still preserved")
    }

    func testRecordWakeDedupesAcrossRepresentationsAndZones() {
        let moscow = calendar("Europe/Moscow")
        let dubai = calendar("Asia/Dubai")
        let store = WakeEventStore(defaults: defaults)

        store.recordWake(on: date(2026, 10, 25, 7, 0, in: moscow), calendar: moscow)
        // Same civil day, seen from another zone — a second entry would mean
        // the upgrade path can still double-record one morning.
        store.recordWake(on: date(2026, 10, 25, 8, 0, in: dubai), calendar: dubai)

        XCTAssertEqual(store.wakeDays().count, 1)
        XCTAssertEqual(store.wakeTimes().count, 1)
    }

    // MARK: - Streak oracle

    func testStreakSurvivesTimezoneChange_legacyRawRow() {
        let moscow = calendar("Europe/Moscow")
        let dubai = calendar("Asia/Dubai")
        let storedMoscowDay = moscow.startOfDay(for: date(2026, 10, 25, 7, 0, in: moscow))

        // Pre-fix this compared instants: Dubai's 2026-10-25 midnight is
        // 20:00Z, the stored row is 21:00Z, no match → streak 0.
        XCTAssertNotEqual(storedMoscowDay, dubai.startOfDay(for: date(2026, 10, 25, 8, 0, in: dubai)))

        let streak = StreakCalculator.currentStreak(
            transactions: [],
            wakeDays: [storedMoscowDay],
            now: date(2026, 10, 25, 8, 0, in: dubai),
            calendar: dubai
        )

        XCTAssertEqual(streak, 1, "A recorded morning must keep counting after a timezone change")
    }

    func testStreakSurvivesTimezoneChange_canonicalStoreRow() {
        let moscow = calendar("Europe/Moscow")
        let dubai = calendar("Asia/Dubai")
        let store = WakeEventStore(defaults: defaults)
        store.recordWake(on: date(2026, 10, 25, 7, 0, in: moscow), calendar: moscow)

        let streak = StreakCalculator.currentStreak(
            transactions: [],
            wakeDays: store.wakeDays(),
            now: date(2026, 10, 25, 8, 0, in: dubai),
            calendar: dubai
        )

        XCTAssertEqual(streak, 1)
    }

    // MARK: - Heatmap oracle

    func testHeatmapMarksWokeDayAfterTimezoneChange() {
        let moscow = calendar("Europe/Moscow")
        let dubai = self.calendar("Asia/Dubai", mondayFirst: true)
        let storedMoscowDay = moscow.startOfDay(for: date(2026, 10, 25, 7, 0, in: moscow))

        let grid = StatisticsViewModel.monthGrid(
            today: date(2026, 10, 25, 8, 0, in: dubai),
            snoozesByDay: [:],
            wakeDays: [storedMoscowDay],
            calendar: dubai
        )

        let wokeCell = grid.first { $0.date == dubai.startOfDay(for: date(2026, 10, 25, in: dubai)) }
        let previousCell = grid.first { $0.date == dubai.startOfDay(for: date(2026, 10, 24, in: dubai)) }

        XCTAssertEqual(wokeCell?.status, .woke, "The recorded morning must still render as «встал»")
        XCTAssertEqual(previousCell?.status, .empty, "The identity must not spill onto the previous day")
    }

    // MARK: - Savings oracle

    func testSavingsCountCleanMorningAfterTimezoneChange() {
        let moscow = calendar("Europe/Moscow")
        let dubai = self.calendar("Asia/Dubai", mondayFirst: true)
        let storedMoscowDay = moscow.startOfDay(for: date(2026, 10, 25, 7, 0, in: moscow))

        // 2026-10-25 is a Sunday: the seventh Monday-first column.
        let days = StatisticsViewModel.weekMoneyDays(
            today: date(2026, 10, 25, 8, 0, in: dubai),
            inputs: StatisticsViewModel.MoneyInputs(
                wakeDays: [storedMoscowDay], snoozePrice: 50
            ),
            currency: .rub,
            calendar: dubai
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days[6].isCleanWake, "A clean morning must not stop counting after a timezone change")
        XCTAssertEqual(days[6].saved, 50)

        let summary = StatisticsViewModel.moneySummary(days: days)
        XCTAssertEqual(summary.observedDays, 1)
        XCTAssertEqual(summary.saved, 50, "The ledger is empty, savings are the counterfactual price")
    }
}
