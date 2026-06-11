import XCTest
@testable import SnoozePay

/// Unit tests for AlarmsListViewModel helper methods — detail and penalty formatting.
final class AlarmsListViewModelTests: XCTestCase {

    /// Synchronous stub scheduler for tests that don't care about the
    /// scheduling outcome. Resolves `.success(())` immediately so the VM's
    /// completion-driven rollback path (#129) is exercised on the happy
    /// branch without bringing up `UNUserNotificationCenter`. Tests that
    /// need to verify the failure branch swap in their own stub.
    final class StubScheduler: AlarmScheduling {
        var scheduleResult: Result<Void, AlarmScheduler.SchedulingError> = .success(())
        private(set) var scheduledIDs: [UUID] = []
        private(set) var cancelledIDs: [UUID] = []
        /// Fired synchronously inside `schedule` BEFORE the completion runs.
        /// Lets tests sabotage the store between the optimistic persist and
        /// the VM's failure-rollback persist (#205 rollback-fails path).
        var onSchedule: (() -> Void)?

        func schedule(
            _ alarm: Alarm,
            completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?
        ) {
            scheduledIDs.append(alarm.id)
            onSchedule?()
            completion?(scheduleResult)
        }

        func cancel(_ alarmID: UUID) {
            cancelledIDs.append(alarmID)
        }
    }

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var stubScheduler: StubScheduler!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmsList.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        stubScheduler = StubScheduler()
        repo = AlarmRepository(defaults: testDefaults, scheduler: stubScheduler)
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
        XCTAssertEqual(penalty, "▲ ПОСПАТЬ ЕЩЁ: −50\u{202F}₽")
    }

    func testAlarmPenaltyString_highPenalty() {
        let alarm = Alarm(penaltyAmount: 1000)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let penalty = vm.alarmPenaltyString(at: 0)
        XCTAssertEqual(penalty, "▲ ПОСПАТЬ ЕЩЁ: −1\u{00A0}000\u{202F}₽")
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

    /// `toggleAlarm` mutates the cached `Alarm` copy in place (#205) — every
    /// non-`enabled` field MUST round-trip unchanged. The previous manual
    /// field-by-field `Alarm(...)` rebuild silently reset any field it didn't
    /// list (it dropped `volume`/`volumeFadeIn`/`theme` from #150/#151 back to
    /// their defaults — the failure mode suspected in #18). Non-default values
    /// for ALL fields keep this a regression fence: a future revert to the
    /// rebuild style trips the assertions immediately.
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
            enabled: true,
            volume: 0.4,
            volumeFadeIn: true,
            theme: .ocean
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
        XCTAssertEqual(cached.volume, original.volume, "#150 volume must survive a toggle")
        XCTAssertEqual(cached.volumeFadeIn, original.volumeFadeIn, "#150 fade-in must survive a toggle")
        XCTAssertEqual(cached.theme, original.theme, "#151 theme must survive a toggle")
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

    /// Issue #117: when `setEnabled` returns false because the persisted
    /// alarms blob became corrupt mid-session, the rollback read must use
    /// the checked variant and surface a `decodeFailure` to the VC. Before
    /// this fix the VM read via `fetchAll()`, got `[]`, and the user saw the
    /// toggle snap back with no banner explaining why.
    func testToggleAlarm_corruptStoreDuringRollback_firesDecodeFailure() {
        // 1. Healthy load.
        let alarm = Alarm(name: "Rollback", penaltyAmount: 50, enabled: true)
        repo.save(alarm)
        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarms.count, 1)

        // 2. Corrupt the store after the initial load — the next setEnabled
        //    will fail (lastLoadFailed-armed inside the lock) and the VM
        //    enters the rollback branch.
        testDefaults.set(Data("garbage".utf8), forKey: "stored_alarms")

        var receivedError: LocalizedError?
        var rebindFired = false
        vm.onLoadError = { receivedError = $0 }
        vm.onAlarmsUpdated = { rebindFired = true }

        vm.toggleAlarm(id: alarm.id, enabled: false)

        XCTAssertTrue(rebindFired, "Rollback path must trigger a UI re-bind")
        XCTAssertNotNil(receivedError, "Decode failure during rollback must surface to the VC")
        if let typed = receivedError as? AlarmRepository.RepositoryError,
           case .decodeFailure = typed {
            // expected — the error must be the original decode failure, not a
            // generic persistBlocked, so the user sees the right message.
        } else {
            XCTFail("Expected decodeFailure, got \(String(describing: receivedError))")
        }
        XCTAssertTrue(vm.alarms.isEmpty,
                      "Rollback after a decode failure must clear the in-memory snapshot")
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

    // MARK: - Issue #129: surfaced scheduling errors from list toggle

    /// When `UNUserNotificationCenter.add` fails (revoked permission, malformed
    /// trigger, 64-pending limit) during a list toggle, the VM must surface the
    /// underlying `AlarmScheduler.SchedulingError` to the VC AND roll the
    /// in-memory `enabled` flag back so the cell switch matches the user's
    /// actual notification state. Before this fix the toggle landed in
    /// UserDefaults with `enabled=true` while the notification never registered
    /// — silent failure (audit-finding from #127).
    func testToggleAlarm_schedulingFailure_firesOnLoadErrorAndRollsBackEnabled() {
        let alarm = Alarm(name: "ToggleOn", penaltyAmount: 50, enabled: false)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarms.count, 1)
        XCTAssertFalse(vm.alarms[0].enabled, "Pre-condition: alarm starts disabled")

        // Stub the scheduler to mimic a denied-permission rejection from
        // UNUserNotificationCenter. The VM must observe the failure and
        // unwind the optimistic enable.
        let underlying = "Notifications are not allowed for this application"
        stubScheduler.scheduleResult = .failure(.system(message: underlying))

        var receivedError: LocalizedError?
        var rebindFired = false
        vm.onLoadError = { receivedError = $0 }
        vm.onAlarmsUpdated = { rebindFired = true }

        vm.toggleAlarm(id: alarm.id, enabled: true)

        // Error must reach the VC verbatim through the existing onLoadError
        // channel — `SchedulingError` is itself `LocalizedError`, no new
        // callback needed.
        XCTAssertTrue(rebindFired, "VM must trigger a re-bind so the cell switch rolls back")
        guard let typed = receivedError as? AlarmScheduler.SchedulingError else {
            return XCTFail("Expected AlarmScheduler.SchedulingError, got \(String(describing: receivedError))")
        }
        if case .system(let message) = typed {
            XCTAssertEqual(message, underlying, "UN error must reach the VM verbatim")
        } else {
            XCTFail("Expected .system, got \(typed)")
        }
        XCTAssertFalse(
            vm.alarms[0].enabled,
            "In-memory `enabled` must roll back to the pre-toggle state on schedule failure"
        )
    }

    /// Issue #205: when the schedule fails AND the disk rollback `setEnabled`
    /// call ALSO fails (store corrupted mid-flight / alarm deleted
    /// concurrently), the VM must not swallow the rollback boolean. In-memory
    /// says `enabled=false` while disk still says `enabled=true` — next cold
    /// launch re-reads enabled=true with no notification scheduled, the exact
    /// silent regression #129 closed. The VM must surface the stronger
    /// `ToggleError.rollbackPersistFailed` banner instead of the plain
    /// scheduling error.
    func testToggleAlarm_rollbackPersistFails_surfacesToggleError() {
        let alarm = Alarm(name: "RollbackFail", penaltyAmount: 50, enabled: false)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarms.count, 1)

        // The optimistic persist (enabled=true) succeeds, then `schedule`
        // corrupts the store BEFORE failing — so the VM's rollback
        // `setEnabled(false)` hits a locked store and returns false.
        stubScheduler.scheduleResult = .failure(.system(message: "denied"))
        stubScheduler.onSchedule = { [testDefaults] in
            testDefaults?.set(Data("garbage".utf8), forKey: "stored_alarms")
        }

        var receivedError: LocalizedError?
        var rebindFired = false
        vm.onLoadError = { receivedError = $0 }
        vm.onAlarmsUpdated = { rebindFired = true }

        vm.toggleAlarm(id: alarm.id, enabled: true)

        XCTAssertTrue(rebindFired, "Failed toggle must still trigger a UI re-bind")
        XCTAssertFalse(vm.alarms[0].enabled, "In-memory `enabled` must still roll back")
        guard let typed = receivedError as? AlarmsListViewModel.ToggleError else {
            return XCTFail(
                "Expected ToggleError.rollbackPersistFailed, got \(String(describing: receivedError))"
            )
        }
        XCTAssertEqual(typed, .rollbackPersistFailed)
        XCTAssertNotNil(
            typed.errorDescription,
            "Rollback-failure banner must carry user-facing copy"
        )
    }

    /// Inverse of the failure test: when the scheduler resolves successfully,
    /// the VM must NOT fire `onLoadError` and must NOT rebind — the optimistic
    /// cell flip is already correct, so a redundant table reload would drop
    /// in-flight switch animations.
    func testToggleAlarm_schedulingSuccess_doesNotFireOnLoadError() {
        let alarm = Alarm(name: "Healthy", penaltyAmount: 50, enabled: false)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()
        // Stub defaults to .success(()) — set here for clarity.
        stubScheduler.scheduleResult = .success(())

        var receivedError: LocalizedError?
        var rebindCount = 0
        vm.onLoadError = { receivedError = $0 }
        vm.onAlarmsUpdated = { rebindCount += 1 }

        vm.toggleAlarm(id: alarm.id, enabled: true)

        XCTAssertNil(receivedError, "Successful schedule must not surface an error")
        XCTAssertEqual(rebindCount, 0, "Successful toggle must not refire onAlarmsUpdated")
        XCTAssertTrue(vm.alarms[0].enabled, "In-memory state must reflect the new toggle")
    }

    /// Toggle-OFF must not invoke the scheduler at all (there is no work to
    /// schedule), and the completion path must resolve as success so async
    /// callers don't hang. Belt-and-suspenders against a future regression
    /// that accidentally fires `.failure` for the disabled branch.
    func testToggleAlarm_disablingAlarm_doesNotInvokeScheduler() {
        let alarm = Alarm(name: "ToggleOff", penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()
        // `repo.save(enabled alarm)` above already scheduled once — that is
        // by design. Snapshot the count so the assertion below catches only
        // NEW schedule calls made by the toggle itself.
        let preToggleScheduleCount = stubScheduler.scheduledIDs.count
        // Pre-arm the stub with a failure — disabling MUST NOT consult it.
        stubScheduler.scheduleResult = .failure(.system(message: "should not fire"))

        var receivedError: LocalizedError?
        vm.onLoadError = { receivedError = $0 }

        vm.toggleAlarm(id: alarm.id, enabled: false)

        XCTAssertNil(receivedError, "Disabling must skip the scheduler — no failure path")
        XCTAssertEqual(stubScheduler.scheduledIDs.count, preToggleScheduleCount,
                       "schedule() must not run for enabled=false")
        XCTAssertFalse(vm.alarms[0].enabled, "In-memory state must reflect disable")
    }
}

// MARK: - Balance corruption surfaced to late observer (#206)

/// Tests that cold-start balance corruption (latched in `BalanceService.init`
/// before any UI observer exists) still reaches `onBalanceCorrupted` when the
/// VM registers late — the original notification is dropped, so the VM pulls
/// the queryable state in `loadData()`.
final class AlarmsListViewModelCorruptionTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmsListCorruption.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(
            defaults: testDefaults,
            scheduler: AlarmsListViewModelTests.StubScheduler()
        )
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Builds a VM wired to an isolated BalanceService + NotificationCenter
    /// so corruption scenarios don't touch the shared singletons.
    private func makeFixture(rawBalance: Double) -> (vm: AlarmsListViewModel, service: BalanceService) {
        let center = NotificationCenter()
        testDefaults.set(rawBalance, forKey: "user_balance")
        // Service init runs its corruption probe HERE — before the VM (and
        // its observer) exists. The posted notification is dropped, exactly
        // like the cold-start AppDelegate access in #206.
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)
        let vm = AlarmsListViewModel(
            alarmRepository: repo,
            balanceService: service,
            transactionRepository: TransactionRepository(defaults: testDefaults),
            notificationCenter: center
        )
        return (vm, service)
    }

    /// Cold-start scenario: corruption latches in `BalanceService.init`
    /// (notification dropped — no observer yet), the VM registers late, the
    /// VC binds `onBalanceCorrupted`, then `loadData()` runs. The alert
    /// callback MUST still fire with the original raw value.
    func testLoadData_coldStartCorruption_lateObserverStillAlerted() {
        let (vm, _) = makeFixture(rawBalance: -42.0)

        var receivedRaw: Double?
        vm.onBalanceCorrupted = { receivedRaw = $0 }

        vm.loadData()

        XCTAssertEqual(receivedRaw, -42.0,
                       "Late observer must still learn about init-time corruption")
        XCTAssertEqual(vm.balance, 0,
                       "Corrupt balance must be reported as 0 to the list UI")
    }

    /// The alert must fire once per corruption episode — `loadData()` runs on
    /// every `viewWillAppear`, and the live notification + the pulled state
    /// must not stack into duplicate alerts.
    func testLoadData_corruptionAlertFiresOncePerEpisode() {
        let (vm, _) = makeFixture(rawBalance: -5.0)

        var fireCount = 0
        vm.onBalanceCorrupted = { _ in fireCount += 1 }

        vm.loadData()
        vm.loadData()
        vm.loadData()

        XCTAssertEqual(fireCount, 1, "Corruption alert must be deduped per episode")
    }

    /// Healthy VM must never fire the corruption callback.
    func testLoadData_healthyBalance_doesNotFireCorruptionCallback() {
        let (vm, _) = makeFixture(rawBalance: 150.0)

        var fired = false
        vm.onBalanceCorrupted = { _ in fired = true }

        vm.loadData()

        XCTAssertFalse(fired, "Healthy balance must not surface a corruption alert")
        XCTAssertEqual(vm.balance, 150.0)
    }

    /// `acknowledgeBalanceCorruption()` wipes the corrupt value (service
    /// resets to 0, flag clears) and re-arms the dedupe latch so a FUTURE
    /// corruption episode surfaces a fresh alert.
    func testAcknowledgeBalanceCorruption_resetsServiceAndReArmsAlert() {
        let (vm, service) = makeFixture(rawBalance: -10.0)

        var fireCount = 0
        vm.onBalanceCorrupted = { _ in fireCount += 1 }

        vm.loadData()
        XCTAssertEqual(fireCount, 1)

        vm.acknowledgeBalanceCorruption()
        XCTAssertFalse(service.balanceCorrupted, "Ack must clear the service flag")
        XCTAssertEqual(service.balance, 0, "Ack must reset the stored balance to 0")

        // Healthy reload — no new alert.
        vm.loadData()
        XCTAssertEqual(fireCount, 1)

        // Second corruption episode (external write) must alert again.
        testDefaults.set(-99.0, forKey: "user_balance")
        vm.loadData()
        XCTAssertEqual(fireCount, 2,
                       "A fresh corruption episode after ack must re-fire the alert")
    }
}
