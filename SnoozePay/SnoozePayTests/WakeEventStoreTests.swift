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
        suiteName = "test.wakestore.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        store = WakeEventStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRecordWake_storesCanonicalDayIdentity() {
        let noon = calendar.date(
            bySettingHour: 12, minute: 30, second: 0, of: Date()
        )!
        store.recordWake(on: noon, calendar: calendar)
        // #1064: the row is the civil day's UTC midnight, not this device's
        // `startOfDay`, so the identity survives a later timezone change.
        XCTAssertEqual(
            store.wakeDays().map(WakeDayIdentity.init(storedDay:)),
            [WakeDayIdentity(date: noon, calendar: calendar)]
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

    func testRoundTrip_persistsAcrossInstances() {
        store.recordWake(on: Date(), calendar: calendar)
        let reloaded = WakeEventStore(defaults: testDefaults)
        XCTAssertEqual(reloaded.wakeDays(), store.wakeDays())
    }
}
