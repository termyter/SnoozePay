import XCTest
@testable import SnoozePay

/// Unit tests for AlarmsListViewModel helper methods — detail and penalty formatting.
final class AlarmsListViewModelTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmsList.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeViewModel() -> AlarmsListViewModel {
        AlarmsListViewModel(alarmRepository: repo, balanceService: .shared)
    }

    // MARK: - alarmDetail(at:)

    func testAlarmDetail_withNameAndDays() {
        // Weekdays Mon-Fri (0-4) should display as "Будни"
        let alarm = Alarm(
            repeatDays: [0, 1, 2, 3, 4],
            name: "Работа",
            penaltyAmount: 50
        )
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let detail = vm.alarmDetail(at: 0)
        XCTAssertEqual(detail, "Работа \u{2022} Будни")
    }

    func testAlarmDetail_withNameNoDays() {
        // No repeat days should display as "Единожды"
        let alarm = Alarm(
            repeatDays: [],
            name: "Утро",
            penaltyAmount: 100
        )
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let detail = vm.alarmDetail(at: 0)
        XCTAssertEqual(detail, "Утро \u{2022} Единожды")
    }

    // MARK: - alarmPenaltyString(at:)

    func testAlarmPenaltyString_format() {
        let alarm = Alarm(penaltyAmount: 50)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let penalty = vm.alarmPenaltyString(at: 0)
        XCTAssertEqual(penalty, "▲ ОТЛОЖИТЬ: 50 ₽")
    }

    func testAlarmPenaltyString_highPenalty() {
        let alarm = Alarm(penaltyAmount: 1000)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let penalty = vm.alarmPenaltyString(at: 0)
        XCTAssertEqual(penalty, "▲ ОТЛОЖИТЬ: 1000 ₽")
    }

    // MARK: - Safe index handling

    func testAlarmTimeString_emptyAlarmsReturnsEmptyString() {
        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarmTimeString(at: 0), "")
        XCTAssertEqual(vm.alarmDetail(at: 0), "")
        XCTAssertEqual(vm.alarmPenaltyString(at: 0), "")
    }

    func testFormattedBalance_containsRubleSign() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.formattedBalance.contains("₽"))
    }

    /// Regression for issue #55: the balance banner previously showed "₽ 0 ₽" because
    /// AlarmsListViewController prepended "₽ " to a string that already had a " ₽" suffix.
    /// `formattedBalance` is the single source of truth for the banner — it MUST contain
    /// exactly one ruble glyph, and the controller MUST render it verbatim (no extra prefix).
    func testFormattedBalance_containsExactlyOneRubleSign() {
        let vm = makeViewModel()
        let occurrences = vm.formattedBalance.filter { $0 == "₽" }.count
        XCTAssertEqual(
            occurrences, 1,
            "formattedBalance must contain exactly one ₽ symbol — saw \"\(vm.formattedBalance)\""
        )
    }

    /// Sibling assertion to `testFormattedBalance_containsExactlyOneRubleSign`:
    /// the formatted string must end with the ruble suffix (Russian convention is
    /// "X ₽", not "₽X"). A regression toward prefix style would silently break the
    /// banner layout; encode the convention explicitly here.
    func testFormattedBalance_endsWithRubleSuffix() {
        let vm = makeViewModel()
        XCTAssertTrue(
            vm.formattedBalance.hasSuffix("₽"),
            "formattedBalance must end with ₽ (suffix style); got \"\(vm.formattedBalance)\""
        )
        XCTAssertFalse(
            vm.formattedBalance.hasPrefix("₽"),
            "formattedBalance must NOT start with ₽; got \"\(vm.formattedBalance)\""
        )
    }

    // MARK: - toggleAlarm(id:enabled:)

    func testToggleAlarm_updatesInMemoryState() {
        let alarm = Alarm(penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()
        XCTAssertTrue(vm.alarms[0].enabled)

        vm.toggleAlarm(id: vm.alarms[0].id, enabled: false)
        XCTAssertFalse(vm.alarms[0].enabled, "In-memory alarm must reflect the new enabled state immediately")
    }

    func testToggleAlarm_persistsToRepository() {
        let alarm = Alarm(penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        vm.toggleAlarm(id: vm.alarms[0].id, enabled: false)
        let stored = repo.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertFalse(stored[0].enabled, "Toggle must persist through the repository")
    }

    // MARK: - Coverage gaps surfaced by pr-test-analyzer (#32)

    /// `toggleAlarm` rebuilds the in-memory cache via the positional `Alarm(...)`
    /// initializer. Every non-`enabled` field MUST round-trip unchanged — if a
    /// future model field is added but the rebuild block is not updated, that
    /// field would silently revert to the default on toggle (the suspected
    /// root cause of #18). This is a regression fence: any new field plus a
    /// changed default value will trip the assertion.
    func testToggleAlarm_persistsAndRebuildsCacheCorrectly() {
        let calendar = Calendar(identifier: .gregorian)
        let time = calendar.date(from: DateComponents(hour: 7, minute: 30))!
        let original = Alarm(
            time: time,
            repeatDays: [1, 3, 5],
            name: "Тренировка",
            soundID: "marimba",
            vibrationEnabled: false,
            snoozeMinutes: 7,
            penaltyAmount: 250,
            progressiveScale: true,
            enabled: true
        )
        repo.save(original)

        let vm = makeViewModel()
        vm.loadData()

        vm.toggleAlarm(id: vm.alarms[0].id, enabled: false)

        let cached = vm.alarms[0]
        XCTAssertEqual(cached.id, original.id)
        XCTAssertEqual(cached.time, original.time)
        XCTAssertEqual(cached.repeatDays, original.repeatDays)
        XCTAssertEqual(cached.name, original.name)
        XCTAssertEqual(cached.soundID, original.soundID)
        XCTAssertEqual(cached.vibrationEnabled, original.vibrationEnabled)
        XCTAssertEqual(cached.snoozeMinutes, original.snoozeMinutes)
        XCTAssertEqual(cached.penaltyAmount, original.penaltyAmount)
        XCTAssertEqual(cached.progressiveScale, original.progressiveScale)
        XCTAssertFalse(cached.enabled, "Only `enabled` should change")

        // Repository must mirror the in-memory state.
        let stored = repo.fetch(id: original.id)!
        XCTAssertEqual(stored, cached, "In-memory cache must equal persisted state after toggle")
    }

    /// Happy-path toggle (alarm exists in repo) MUST NOT call `onAlarmsUpdated`.
    /// The current implementation updates the in-place cache and returns silently
    /// — the cell already reflects the optimistic state. A regression that fired
    /// the callback on every toggle would force a full table reload, dropping
    /// in-flight cell animations and re-running every cellForRow path.
    func testToggleAlarm_emitsOnAlarmsUpdatedExactlyOnce() {
        let alarm = Alarm(penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel()
        var emissions = 0
        vm.onAlarmsUpdated = { emissions += 1 }

        vm.loadData()
        // loadData() MUST emit once (initial bind). Reset the counter so the
        // toggle assertion below isolates the toggle's own emissions.
        XCTAssertEqual(emissions, 1, "loadData must emit onAlarmsUpdated exactly once on initial load")
        emissions = 0

        vm.toggleAlarm(id: vm.alarms[0].id, enabled: false)

        XCTAssertEqual(
            emissions, 0,
            "Successful toggle must not refire onAlarmsUpdated — the cell already shows the new state"
        )
    }

    // MARK: - toggleAlarm(id:enabled:)

    /// Regression for issue #35: when the alarm exists in the VM's in-memory snapshot
    /// but has been deleted from the repository (e.g. via another tab/path), `setEnabled`
    /// must report failure and the VM must resync from the repo + trigger a re-bind so
    /// the optimistic switch flip in the cell rolls back.
    func testToggleAlarm_repoMissingTriggersResyncAndRebind() {
        let alarm = Alarm(penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarms.count, 1)

        // Simulate a parallel delete that bypassed the VM (the VM still has the
        // alarm in its in-memory snapshot, but the repository no longer does).
        repo.delete(id: alarm.id)

        var rebindFired = false
        vm.onAlarmsUpdated = { rebindFired = true }

        vm.toggleAlarm(id: alarm.id, enabled: false)

        XCTAssertTrue(rebindFired, "VM must trigger a UI re-bind so the cell switch rolls back")
        XCTAssertTrue(vm.alarms.isEmpty, "VM must resync from the repository after a missing-id failure")
    }

    /// Regression for tag-based identity bug: when middle alarm is removed and the
    /// caller toggles the *first* alarm, only that alarm — resolved by id — must flip,
    /// not whichever alarm currently lives at the captured row index.
    func testToggleAlarmByID_correctAlarmTogglesAfterDelete() {
        // Three alarms with distinct times so sort order is stable: 06:00, 07:00, 08:00.
        let calendar = Calendar(identifier: .gregorian)
        let date6 = calendar.date(from: DateComponents(hour: 6, minute: 0))!
        let date7 = calendar.date(from: DateComponents(hour: 7, minute: 0))!
        let date8 = calendar.date(from: DateComponents(hour: 8, minute: 0))!

        let first = Alarm(time: date6, name: "Early", penaltyAmount: 50, enabled: true)
        let middle = Alarm(time: date7, name: "Mid", penaltyAmount: 50, enabled: true)
        let last = Alarm(time: date8, name: "Late", penaltyAmount: 50, enabled: true)
        repo.save(first)
        repo.save(middle)
        repo.save(last)

        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarms.map(\.id), [first.id, middle.id, last.id])

        // Capture the first alarm's id BEFORE deletion — this is what an
        // already-configured cell would have closed over.
        let firstID = first.id

        vm.deleteAlarm(at: 1) // remove "Mid"
        XCTAssertEqual(vm.alarms.map(\.id), [first.id, last.id])

        vm.toggleAlarm(id: firstID, enabled: false)

        // Only "Early" should have flipped — "Late" stays enabled.
        let early = vm.alarms.first { $0.id == first.id }
        let late = vm.alarms.first { $0.id == last.id }
        XCTAssertEqual(early?.enabled, false, "The alarm matching the captured id must toggle")
        XCTAssertEqual(late?.enabled, true, "Sibling alarms must NOT be affected by an id-targeted toggle")
    }

    // MARK: - Issue #72: surfaced load errors

    /// When the underlying repository can't decode the persisted blob, the
    /// VM must fire `onLoadError` AND keep the alarms list empty so the VC
    /// can show an alert + the empty state simultaneously.
    func testLoadData_corruptedJSON_firesOnLoadError() {
        testDefaults.set(Data("not json".utf8), forKey: "stored_alarms")

        let vm = makeViewModel()
        var receivedError: LocalizedError?
        vm.onLoadError = { receivedError = $0 }

        vm.loadData()

        XCTAssertNotNil(receivedError, "VM must propagate decode failures to the VC")
        if let typed = receivedError as? AlarmRepository.RepositoryError,
           case .decodeFailure = typed {
            // expected
        } else {
            XCTFail("Expected decodeFailure, got \(String(describing: receivedError))")
        }
        XCTAssertTrue(vm.alarms.isEmpty)
    }

    /// When the store gets locked AFTER a successful initial load, the user
    /// might still try to delete an alarm from the cached snapshot. The VM
    /// must surface the persist failure so the swipe-to-delete UX doesn't
    /// silently succeed (issue #72).
    func testDelete_whileStoreLockedAfterLoad_firesOnLoadError() {
        // 1. Save valid alarm and load — VM caches it in memory.
        let alarm = Alarm(name: "ToDelete", penaltyAmount: 50)
        repo.save(alarm)
        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarms.count, 1)

        // 2. Corrupt the store out from under the VM.
        testDefaults.set(Data("corrupt".utf8), forKey: "stored_alarms")
        // Touching the repo's checked read arms the lock.
        _ = try? repo.fetchAllChecked()

        var receivedError: LocalizedError?
        vm.onLoadError = { receivedError = $0 }

        let didDelete = vm.deleteAlarm(id: alarm.id)
        XCTAssertFalse(didDelete, "Delete must report failure when the store is locked")
        XCTAssertNotNil(receivedError, "VM must propagate the persist block to the VC")
        XCTAssertEqual(vm.alarms.count, 1,
                       "In-memory snapshot must NOT shrink when persistence is refused")
    }
}
