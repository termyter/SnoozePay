import XCTest
@testable import SnoozePay

/// Unit tests for the weekly / one-shot repeat mode added in #229:
/// - `Alarm.repeatMode` defaults, `with(...)` mutator, and the
///   backwards-compatible / sanitizing Codable decode (legacy alarms without
///   the key, unknown raw values).
/// - Trigger planning for the two modes now lives on the AlarmKit side and is
///   pinned by `AlarmKitSchedulerTests` (`makeSchedule` maps `.weekly` to a
///   weekly recurrence and `.never` to `.never`); the notification-trigger
///   equivalents that used to be asserted here went away with #472.
/// - `AlarmFiringViewModel.dismiss` auto-disables one-shot alarms and keeps
///   weekly alarms enabled.
/// - `CreateAlarmViewModel` seeding + persistence of the new field.
final class AlarmRepeatModeTests: XCTestCase {

    /// The alarm and wake-day stores the dismiss and save tests write through,
    /// in a per-test suite dropped in `tearDown` (#814). They used to save into
    /// `AlarmRepository(defaults: .standard)` and delete afterwards — which on
    /// a clean host still leaves an encoded empty `stored_alarms` behind — and
    /// the dismiss tests recorded today's wake into `WakeEventStore.shared`,
    /// i.e. `wake_days` / `wake_times` in the host's real `UserDefaults.standard`.
    /// CI run 35861930577 could not see either: earlier tests had already put
    /// all three keys there, and re-saving the same day changes nothing.
    private var suiteName: String!
    private var defaults: UserDefaults!
    /// Fails the test if it moved the host's real `UserDefaults.standard`
    /// (#830). The three `CreateAlarmViewModel` calls built without a
    /// repository still use the view model's `.shared` defaults; they only
    /// read, and this is what keeps it so.
    private var domainGuard: AppDefaultsDomainGuard!

    override func setUp() {
        super.setUp()
        domainGuard = AppDefaultsDomainGuard()
        suiteName = "test.repeatMode.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        domainGuard.assertUntouched()
        domainGuard = nil
        super.tearDown()
    }

    private func makeFiringViewModel(_ alarm: Alarm, repo: AlarmRepository) -> AlarmFiringViewModel {
        AlarmFiringViewModel(
            alarm: alarm,
            snoozeCount: 0,
            balanceService: BalanceService(defaults: defaults, notificationCenter: NotificationCenter()),
            alarmRepository: repo,
            wakeStore: WakeEventStore(defaults: defaults),
            ledger: TransactionRepository(defaults: defaults)
        )
    }

    // MARK: - Model defaults + with(...)

    func testDefaultInit_repeatModeIsWeekly() {
        XCTAssertEqual(Alarm().repeatMode, .weekly,
                       "New alarms must default to the historical weekly behaviour")
    }

    func testValidatingInit_acceptsNeverMode() {
        let alarm = Alarm(validating: UUID(), repeatDays: [0, 2], repeatMode: .never)
        XCTAssertEqual(alarm?.repeatMode, .never)
    }

    func testWith_repeatMode_changesOnlyRepeatMode() {
        let original = Alarm(repeatDays: [0, 4], name: "Утро", penaltyAmount: 100)

        let oneShot = original.with(repeatMode: .never)

        XCTAssertEqual(oneShot.repeatMode, .never)
        XCTAssertEqual(oneShot.id, original.id, "with(...) must preserve identity")
        XCTAssertEqual(oneShot.repeatDays, original.repeatDays)
        XCTAssertEqual(oneShot.name, original.name)
        XCTAssertEqual(oneShot.penaltyAmount, original.penaltyAmount)
    }

    func testWith_otherField_preservesRepeatMode() {
        let oneShot = Alarm(repeatDays: [1], repeatMode: .never)
        XCTAssertEqual(oneShot.with(enabled: false).repeatMode, .never)
    }

    // MARK: - Codable round-trip

    func testEncodeDecode_roundTripsNeverMode() throws {
        let alarm = Alarm(repeatDays: [0, 3], repeatMode: .never)

        let data = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)

        XCTAssertEqual(decoded.repeatMode, .never)
        XCTAssertEqual(decoded.id, alarm.id)
        XCTAssertEqual(decoded.repeatDays, alarm.repeatDays)
    }

    func testEncodeDecode_roundTripsWeeklyMode() throws {
        let alarm = Alarm(repeatDays: [5, 6], repeatMode: .weekly)

        let data = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)

        XCTAssertEqual(decoded.repeatMode, .weekly)
    }

    // MARK: - Legacy decode (pre-#229 payloads)

    /// Strip the `repeatMode` key from an encoded alarm to simulate a
    /// pre-#229 persisted payload, then decode it back.
    private func decodeWithoutRepeatModeKey(_ alarm: Alarm) throws -> Alarm {
        let data = try JSONEncoder().encode(alarm)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json.removeValue(forKey: "repeatMode")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Alarm.self, from: legacyData)
    }

    func testDecode_missingRepeatModeKey_defaultsToWeekly() throws {
        let legacy = try decodeWithoutRepeatModeKey(Alarm(repeatDays: [0, 1, 2, 3, 4]))
        XCTAssertEqual(legacy.repeatMode, .weekly,
                       "Pre-#229 alarms must keep their historical weekly behaviour")
    }

    func testDecode_missingRepeatModeKey_preservesOtherFields() throws {
        let original = Alarm(repeatDays: [2], name: "Зал", penaltyAmount: 75)
        let legacy = try decodeWithoutRepeatModeKey(original)
        XCTAssertEqual(legacy.id, original.id)
        XCTAssertEqual(legacy.repeatDays, original.repeatDays)
        XCTAssertEqual(legacy.name, original.name)
        XCTAssertEqual(legacy.penaltyAmount, original.penaltyAmount)
    }

    func testDecode_unknownRepeatModeRawValue_sanitizesToWeekly() throws {
        // Corrupt storage / rolled-back future mode must not throw — a throw
        // would lock the entire persisted store (#72 / #117).
        let data = try JSONEncoder().encode(Alarm(repeatDays: [0]))
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json["repeatMode"] = "monthly"
        let corruptData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Alarm.self, from: corruptData)

        XCTAssertEqual(decoded.repeatMode, .weekly)
    }

    // MARK: - Dismiss semantics (one-shot auto-disable)

    func testDismiss_oneShotAlarmWithDays_isDisabled() {
        let repo = AlarmRepository(defaults: defaults)
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4], enabled: true, repeatMode: .never)
        repo.save(alarm)

        let viewModel = makeFiringViewModel(alarm, repo: repo)
        viewModel.dismiss()

        XCTAssertEqual(repo.fetchOrFail(id: alarm.id)?.enabled, false,
                       "One-shot alarm must auto-disable after dismiss")
    }

    func testDismiss_weeklyAlarmWithDays_staysEnabled() {
        let repo = AlarmRepository(defaults: defaults)
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4], enabled: true, repeatMode: .weekly)
        repo.save(alarm)

        let viewModel = makeFiringViewModel(alarm, repo: repo)
        viewModel.dismiss()

        XCTAssertEqual(repo.fetchOrFail(id: alarm.id)?.enabled, true,
                       "Weekly alarms keep firing every week — dismiss must not disable them")
    }

    // MARK: - CreateAlarmViewModel seeding + persistence

    /// Was `defaultsToWeekly` until #633. A new form has no days selected, and
    /// «Еженедельно» without days is not a schedule the app can build — it used
    /// to save as a one-shot alarm while the pill still read «Еженедельно».
    /// The form now opens in the mode it would actually save.
    func testCreateVM_newAlarm_defaultsToNeverWhileNoDaysAreSelected() {
        let viewModel = CreateAlarmViewModel()
        XCTAssertTrue(viewModel.repeatDays.isEmpty)
        XCTAssertEqual(viewModel.repeatMode, .never)
    }

    func testCreateVM_editingOneShotAlarm_seedsNever() {
        let alarm = Alarm(repeatDays: [3], repeatMode: .never)
        XCTAssertEqual(CreateAlarmViewModel(alarm: alarm).repeatMode, .never)
    }

    func testCreateVM_save_persistsRepeatMode() {
        let repo = AlarmRepository(defaults: defaults)
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.repeatDays = [0, 2]
        viewModel.repeatMode = .never

        XCTAssertTrue(viewModel.save())

        let saved = repo.fetchAllOrFail().first { $0.repeatDays == [0, 2] && $0.repeatMode == .never }
        XCTAssertNotNil(saved, "Saved alarm must carry the one-shot mode")
    }

    func testCreateVM_hintMatchesMode() {
        let viewModel = CreateAlarmViewModel()
        // With days selected, so the hints read as they did before #633 — the
        // zero-day wording is asserted in `CreateAlarmRepeatValidityTests`.
        viewModel.toggleDay(0)

        viewModel.repeatMode = .never
        XCTAssertEqual(
            viewModel.repeatModeHint,
            "Будильник сработает в выбранные дни один раз и отключится."
        )

        viewModel.repeatMode = .weekly
        XCTAssertEqual(
            viewModel.repeatModeHint,
            "Будет повторяться каждую неделю по выбранным дням."
        )
    }
}
