import XCTest
@testable import SnoozePay

/// Unit tests for WakeEventStore (#235) — the per-day "user got up" signal
/// behind the statistics heatmap's "встал сразу" cells.
final class WakeEventStoreTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var store: WakeEventStore!
    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        let isolated = makeIsolatedSuite()
        testDefaults = isolated.defaults
        suiteName = isolated.name
        store = WakeEventStore(defaults: testDefaults)
    }

    func testRecordWake_storesCanonicalDayIdentity() {
        var moscow = Calendar(identifier: .gregorian)
        moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let instant = moscow.date(from: DateComponents(
            year: 2026, month: 10, day: 25, hour: 7, minute: 30
        ))!
        store.recordWake(on: instant, calendar: moscow)

        // #1064: the row is the civil day's UTC midnight — 2026-10-25T00:00Z —
        // not a `startOfDay` carrying this device's offset (21:00Z here).
        let expected = WakeDayIdentity(year: 2026, month: 10, day: 25).canonicalStoredDay!
        XCTAssertEqual(store.wakeDays(), [expected])
        XCTAssertEqual(
            store.wakeDays().map(WakeDayIdentity.init(storedDay:)),
            [WakeDayIdentity(year: 2026, month: 10, day: 25)]
        )
    }

    func testRecordWake_sameDayTwice_dedupes() {
        // Anchor mid-day so +1h can never cross midnight — Date()+3600 made
        // this test fail on any CI run between 23:00 and 00:00 (two distinct
        // calendar days → count 2).
        let morning = calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: Date()
        )!
        store.recordWake(on: morning, calendar: calendar)
        store.recordWake(
            on: morning.addingTimeInterval(3600), calendar: calendar
        )
        XCTAssertEqual(store.wakeDays().count, 1,
                       "Repeat dismissals on the same day must collapse to one entry")
    }

    func testRecordWake_distinctDays_keepsBoth() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        store.recordWake(on: yesterday, calendar: calendar)
        store.recordWake(on: today, calendar: calendar)
        XCTAssertEqual(store.wakeDays().count, 2)
    }

    func testRecordWake_prunesDaysBeyondRetention() {
        let ancient = calendar.date(byAdding: .day, value: -500, to: Date())!
        // Pruning is keyed off "now" on every write, so the 500-day-old
        // entry is dropped before it ever hits the blob.
        store.recordWake(on: ancient, calendar: calendar)
        store.recordWake(on: Date(), calendar: calendar)
        let today = WakeDayIdentity(date: Date(), calendar: calendar)
        XCTAssertEqual(store.wakeDays().map(WakeDayIdentity.init(storedDay:)), [today],
                       "Entries older than the retention window must be pruned")
    }

    func testWakeDays_corruptBlob_degradesToEmpty() {
        testDefaults.set(Data("not json".utf8), forKey: "wake_days")
        XCTAssertTrue(store.wakeDays().isEmpty,
                      "Corrupt blob degrades to empty — heatmap falls back to dark cells")
    }

    // MARK: - Unreadable history is never overwritten (#1097)

    func testRecordWake_unreadableDays_keepsBlobAndStillRecordsInstant() {
        let damaged = Data("damaged wake days".utf8)
        testDefaults.set(damaged, forKey: "wake_days")
        let now = Date()

        store.recordWake(on: now, calendar: calendar)

        XCTAssertEqual(testDefaults.data(forKey: "wake_days"), damaged,
                       "A dismissal must not replace a damaged history with one fresh row")
        XCTAssertEqual(store.readSnapshot().days, .unreadable,
                       "Statistics must keep reporting the history as unavailable")
        let times = store.wakeTimes()
        XCTAssertEqual(times.count, 1, "The readable sibling key still records")
        XCTAssertEqual(times.first?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testRecordWake_unreadableTimes_keepsBlobAndStillRecordsDay() {
        let damaged = Data("damaged wake times".utf8)
        testDefaults.set(damaged, forKey: "wake_times")
        let now = Date()

        store.recordWake(on: now, calendar: calendar)

        XCTAssertEqual(testDefaults.data(forKey: "wake_times"), damaged)
        XCTAssertEqual(store.readSnapshot().times, .unreadable)
        XCTAssertEqual(store.wakeDays().map(WakeDayIdentity.init(storedDay:)),
                       [WakeDayIdentity(date: now, calendar: calendar)])
    }

    func testRecordWake_bothUnreadable_writesNothing() {
        testDefaults.set(42, forKey: "wake_days")
        testDefaults.set(Data("damaged wake times".utf8), forKey: "wake_times")
        let before = testDefaults.persistentDomain(forName: suiteName) ?? [:]

        store.recordWake(on: Date(), calendar: calendar)

        let after = testDefaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertEqual(after as NSDictionary, before as NSDictionary)
    }

    func testRoundTrip_persistsAcrossInstances() {
        store.recordWake(on: Date(), calendar: calendar)
        let reloaded = WakeEventStore(defaults: testDefaults)
        XCTAssertEqual(reloaded.wakeDays(), store.wakeDays())
    }
}
