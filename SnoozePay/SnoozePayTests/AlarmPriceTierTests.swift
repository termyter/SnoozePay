import XCTest
import os
@testable import SnoozePay

/// #1127: the snooze-price tier an alarm stores — corrupt values on disk, and
/// every path that rebuilds an alarm from another one.
final class AlarmPriceTierTests: XCTestCase {

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)

    private static func payload(tier: String) -> String {
        """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","time":721692800,"repeatDays":[],"name":"Зал",\
        "nameIsDefault":false,"soundID":"radar","vibrationEnabled":true,"snoozeMinutes":9,\
        "penaltyAmount":100,"penaltyTier":\(tier),"progressiveScale":false,"enabled":true}
        """
    }

    // MARK: - Unknown tier on disk

    /// A tier this build does not know — a future raw value, `null`, a string —
    /// keeps the alarm, falls back to `penaltyAmount`, and says so in the log.
    func testDecode_unknownTier_fallsBackToAmountAndLogs() throws {
        for raw in ["0", "4", "99", "null", "\"mid\"", "1.5"] {
            var lines: [LoggedLine] = []
            let alarm = try AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
                try JSONDecoder().decode(Alarm.self, from: Data(Self.payload(tier: raw).utf8))
            })
            XCTAssertNil(alarm.penaltyTier, raw)
            XCTAssertEqual(alarm.price, .amount(100), raw)
            XCTAssertEqual(alarm.customName, "Зал", raw)
            XCTAssertEqual(lines.count, 1, raw)
            XCTAssertEqual(lines.first?.category, .repository, raw)
            XCTAssertEqual(lines.first?.level, .error, raw)
            XCTAssertTrue(lines.first?.message.contains("ALARM-1127-UNKNOWN-TIER") ?? false, raw)
        }
    }

    func testDecode_knownTier_logsNothing() throws {
        var lines: [LoggedLine] = []
        let alarm = try AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            try JSONDecoder().decode(Alarm.self, from: Data(Self.payload(tier: "1").utf8))
        })
        XCTAssertEqual(alarm.price, .tier(.low))
        XCTAssertTrue(lines.isEmpty, "\(lines.map(\.message))")
    }

    // MARK: - price

    func testPrice_isTheTierWhenStoredElseTheAmount() {
        XCTAssertEqual(Alarm(penaltyAmount: 20).price, .amount(20))
        XCTAssertEqual(Alarm(penaltyAmount: 0).price, .amount(0))
        XCTAssertEqual(Alarm(penaltyAmount: 20, penaltyTier: .high).price, .tier(.high))
    }

    /// The legacy charge path ignores the tier — wiring is a later step of #1109.
    func testLegacyPenaltyReadsAreUnchangedByATier() {
        let plain = Alarm(penaltyAmount: 50, progressiveScale: true)
        let tiered = Alarm(penaltyAmount: 50, penaltyTier: .high, progressiveScale: true)
        for count in 0...6 {
            XCTAssertEqual(tiered.penalty(forSnoozeCount: count), plain.penalty(forSnoozeCount: count))
        }
        XCTAssertEqual(tiered.penaltyMoney, plain.penaltyMoney)
    }

    // MARK: - Copies keep the tier

    func testWith_everyFieldCopyKeepsTheTier() {
        let alarm = Alarm(penaltyAmount: 50, penaltyTier: .mid)
        let copies: [(String, Alarm)] = [
            ("no change", alarm.with()),
            ("enabled", alarm.with(enabled: false)),
            ("time", alarm.with(time: Date(timeIntervalSince1970: 0))),
            ("clockTime", alarm.with(clockTime: TimeOfDay(hour: 5, minute: 0))),
            ("repeatDays", alarm.with(repeatDays: [1])),
            ("name", alarm.with(name: "Спорт")),
            ("soundID", alarm.with(soundID: "radar")),
            ("vibration", alarm.with(vibrationEnabled: false)),
            ("snooze", alarm.with(snoozeMinutes: 3)),
            ("penaltyAmount", alarm.with(penaltyAmount: 100)),
            ("progressive", alarm.with(progressiveScale: true)),
            ("volume", alarm.with(volume: 0.3)),
            ("fade", alarm.with(volumeFadeIn: true)),
            ("theme", alarm.with(theme: .ocean)),
            ("repeatMode", alarm.with(repeatMode: .never))
        ]
        for (label, copy) in copies {
            XCTAssertEqual(copy.penaltyTier, .mid, label)
            XCTAssertEqual(copy.id, alarm.id, label)
        }
    }

    func testWith_priceReplacesTheWholePrice() {
        let tiered = Alarm(penaltyAmount: 50, penaltyTier: .mid)

        let toTier = Alarm(penaltyAmount: 50).with(price: .tier(.high))
        XCTAssertEqual(toTier.price, .tier(.high))
        XCTAssertEqual(toTier.penaltyAmount, 50, "a tier keeps the amount older builds read")

        let toAmount = tiered.with(price: .amount(200))
        XCTAssertEqual(toAmount.price, .amount(200))
        XCTAssertNil(toAmount.penaltyTier)

        XCTAssertEqual(tiered.with(penaltyAmount: 20, price: .amount(500)).penaltyAmount, 500)
    }

    // MARK: - The editor rebuilds the alarm field by field

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmPriceTier.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func editor(for alarm: Alarm) -> CreateAlarmViewModel {
        CreateAlarmViewModel(
            alarm: alarm,
            repository: repo,
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available),
                notificationCenter: NotificationCenter()
            )
        )
    }

    func testEditorSave_untouchedPrice_keepsTheTier() {
        let original = Alarm(repeatDays: [0], penaltyAmount: 50, penaltyTier: .high)
        repo.save(original)

        let model = editor(for: original)
        model.snoozeMinutes = 4
        XCTAssertTrue(model.save())

        let saved = repo.fetchAllOrFail().first
        XCTAssertEqual(saved?.price, .tier(.high))
        XCTAssertEqual(saved?.snoozeMinutes, 4)
    }

    func testEditorSave_editedAmount_dropsTheTier() {
        let original = Alarm(repeatDays: [0], penaltyAmount: 50, penaltyTier: .high)
        repo.save(original)

        let model = editor(for: original)
        model.penaltyAmount = 120
        XCTAssertTrue(model.save())

        XCTAssertEqual(repo.fetchAllOrFail().first?.price, .amount(120))
    }
}
