import XCTest
@testable import SnoozePay

/// Unit tests for CreateAlarmViewModel — sound preview, defaults, day toggle, progressive scale.
final class CreateAlarmViewModelSoundTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.createAlarm.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Available sounds

    func testAvailableSounds_hasCorrectCount() {
        let vm = CreateAlarmViewModel(repository: repo)
        XCTAssertEqual(vm.availableSounds.count, 10)
    }

    func testAvailableSounds_allHaveUniqueIDs() {
        let vm = CreateAlarmViewModel(repository: repo)
        let ids = vm.availableSounds.map { $0.id }
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Sound IDs must be unique")
    }

    func testAvailableSounds_allHaveNonEmptyNames() {
        let vm = CreateAlarmViewModel(repository: repo)
        for sound in vm.availableSounds {
            XCTAssertFalse(sound.name.isEmpty, "Sound '\(sound.id)' has empty name")
        }
    }

    // MARK: - Sound preview (should not crash)

    func testPreviewSound_withValidID_doesNotCrash() {
        let vm = CreateAlarmViewModel(repository: repo)
        // Calling previewSound with a valid ID should not crash.
        // AudioServicesPlaySystemSound may be a no-op in test environment.
        XCTAssertTrue(vm.previewSound("dawn"))
        XCTAssertTrue(vm.previewSound("radar"))
        XCTAssertTrue(vm.previewSound("drops"))
    }

    func testPreviewSound_withInvalidID_doesNotCrash() {
        let vm = CreateAlarmViewModel(repository: repo)
        // Unknown IDs are a no-op — previewSound reports it via the
        // Bool result (and logs) instead of failing silently (#210).
        XCTAssertFalse(vm.previewSound("nonexistent_sound"))
        XCTAssertFalse(vm.previewSound(""))
        XCTAssertFalse(vm.previewSound("🎵"))
    }

    /// Drift guard (#210): every sound offered in the picker must have a
    /// preview mapping, otherwise the preview tap is dead for that row.
    func testPreviewSound_coversAllAvailableSounds() {
        let vm = CreateAlarmViewModel(repository: repo)
        for sound in vm.availableSounds {
            XCTAssertTrue(
                vm.previewSound(sound.id),
                "Sound '\(sound.id)' is listed in availableSounds but has no systemSoundMap entry"
            )
        }
    }

    // MARK: - Default values

    func testDefaultValues_areCorrect() {
        let vm = CreateAlarmViewModel(repository: repo)

        // New alarms seed an empty name so the form shows the "Название"
        // placeholder (#231); the save path falls back to "Будильник".
        XCTAssertEqual(vm.name, "")
        XCTAssertEqual(vm.penaltyAmount, 50)
        XCTAssertEqual(vm.snoozeMinutes, 9)
        XCTAssertEqual(vm.soundID, "radar")
        XCTAssertTrue(vm.vibrationEnabled)
        XCTAssertFalse(vm.progressiveScale)
        XCTAssertTrue(vm.enabled)
        XCTAssertTrue(vm.repeatDays.isEmpty)
        XCTAssertFalse(vm.isEditing)
    }

    func testDefaultTime_isSeven() {
        let vm = CreateAlarmViewModel(repository: repo)
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: vm.time)
        let minute = calendar.component(.minute, from: vm.time)
        XCTAssertEqual(hour, 7)
        XCTAssertEqual(minute, 0)
    }

    // MARK: - Day toggle

    func testToggleDay_addsDay() {
        let vm = CreateAlarmViewModel(repository: repo)
        XCTAssertTrue(vm.repeatDays.isEmpty)

        vm.toggleDay(3)
        XCTAssertEqual(vm.repeatDays, [3])
    }

    func testToggleDay_removesExistingDay() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.toggleDay(3)
        XCTAssertEqual(vm.repeatDays, [3])

        vm.toggleDay(3)
        XCTAssertTrue(vm.repeatDays.isEmpty)
    }

    func testToggleDay_maintainsSortedOrder() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.toggleDay(5)
        vm.toggleDay(1)
        vm.toggleDay(3)
        XCTAssertEqual(vm.repeatDays, [1, 3, 5])
    }

    func testToggleDay_allDays() {
        let vm = CreateAlarmViewModel(repository: repo)
        for day in 0...6 {
            vm.toggleDay(day)
        }
        XCTAssertEqual(vm.repeatDays, [0, 1, 2, 3, 4, 5, 6])
    }

    // MARK: - Progressive chain (#231)

    func testProgressiveChain_doublesBaseFourTimes() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 50
        XCTAssertEqual(vm.progressiveChain, [50, 100, 200, 400])
    }

    func testProgressiveChain_tracksPenaltyChanges() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 10
        XCTAssertEqual(vm.progressiveChain, [10, 20, 40, 80])

        vm.penaltyAmount = 200
        XCTAssertEqual(vm.progressiveChain, [200, 400, 800, 1600])
    }

    func testProgressiveChain_nonFinitePenaltyFallsBackToDefaultBase() {
        // Mirrors makeAlarmFromCurrentState's sanitation (#207): garbage
        // penalty input degrades to the 50 ₽ default instead of trapping.
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = .nan
        XCTAssertEqual(vm.progressiveChain, [50, 100, 200, 400])

        vm.penaltyAmount = .infinity
        XCTAssertEqual(vm.progressiveChain, [50, 100, 200, 400])
    }

    func testProgressiveChain_negativePenaltyClampsToZero() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = -25
        XCTAssertEqual(vm.progressiveChain, [0, 0, 0, 0])
    }

    func testProgressiveChain_fractionalPenalty_doublesOnDoubleNotTruncatedInt() {
        // Regression (#373): the old `Int(base) << $0` truncated the fractional
        // rouble *before* doubling (49 → 98 → 196 → 392). The canonical engine
        // `Alarm.penalty` doubles on Double via pow, so the preview must too:
        // 49.5 → 99 → 198 → 396 (the base rounds to 50 for Int display).
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 49.5
        XCTAssertEqual(vm.progressiveChain, [50, 99, 198, 396])
    }

    func testProgressiveChain_largePenalty_clampsInsteadOfTrapping() {
        // Regression (#373): `base << 3` overflowed Int and trapped for large
        // penalties (PenaltyCell enforces only a minimum, no upper bound).
        // The Double path must clamp to Int.max rather than crash.
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 1e19  // > Int.max (~9.22e18)
        XCTAssertEqual(vm.progressiveChain.count, 4)
        XCTAssertEqual(vm.progressiveChain, [.max, .max, .max, .max])
    }

    // MARK: - Progressive scale preview

    func testProgressiveScalePreview_format() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 50
        let preview = vm.progressiveScalePreview
        XCTAssertEqual(preview, "1-е: 50\u{202F}₽ → 2-е: 100\u{202F}₽ → 3-е: 200\u{202F}₽ → 4-е: 400\u{202F}₽")
    }

    func testProgressiveScalePreview_withHighPenalty() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 1000
        let preview = vm.progressiveScalePreview
        XCTAssertEqual(
            preview,
            "1-е: 1\u{00A0}000\u{202F}₽ → 2-е: 2\u{00A0}000\u{202F}₽ → 3-е: 4\u{00A0}000\u{202F}₽ → 4-е: 8\u{00A0}000\u{202F}₽"
        )
    }

    func testProgressiveScalePreview_withMinimumPenalty() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 10
        let preview = vm.progressiveScalePreview
        XCTAssertTrue(preview.hasPrefix("1-е: 10\u{202F}₽"))
        XCTAssertTrue(preview.contains("2-е: 20\u{202F}₽"))
    }

    // MARK: - Progressive scale toggle (regression for #51)

    func testProgressiveScaleToggle_flipsPersistedValue() {
        // Toggling progressiveScale on the ViewModel must mirror through to a
        // saved alarm so the UI toggle on CreateAlarmViewController stays in
        // sync with persisted state. Regression guard for the toggle handler
        // that previously crashed before the value could be saved.
        let vm = CreateAlarmViewModel(repository: repo)
        XCTAssertFalse(vm.progressiveScale)

        vm.progressiveScale = true
        vm.save()
        let saved = repo.fetchAllOrFail().first
        XCTAssertTrue(saved?.progressiveScale ?? false)

        // A non-editing VM mints a fresh UUID per save, so a second save()
        // on the SAME VM would create a second alarm instead of updating the
        // first. Re-open the persisted alarm in edit mode — that is the flow
        // the #51 toggle actually runs through on the edit screen.
        let editVM = CreateAlarmViewModel(alarm: saved, repository: repo)
        XCTAssertTrue(editVM.progressiveScale, "Edit VM must pick up the persisted toggle state")
        editVM.progressiveScale = false
        editVM.save()
        XCTAssertEqual(repo.fetchAllOrFail().count, 1, "Edit-mode save must update, not append")
        XCTAssertFalse(repo.fetchAllOrFail().first?.progressiveScale ?? true)
    }

    func testProgressiveScalePreview_recomputesAfterPenaltyChange() {
        // The CreateAlarmVC toggle handler now refreshes the preview label from
        // `progressiveScalePreview` whenever the toggle flips. Make sure the
        // ViewModel always returns the up-to-date computation (no caching).
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 50
        let firstPreview = vm.progressiveScalePreview

        vm.penaltyAmount = 200
        let secondPreview = vm.progressiveScalePreview

        XCTAssertNotEqual(firstPreview, secondPreview)
        XCTAssertTrue(secondPreview.hasPrefix("1-е: 200\u{202F}₽"))
    }

    // MARK: - Save

    func testSave_createsAlarm() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.name = "Утренний"
        vm.penaltyAmount = 100
        vm.snoozeMinutes = 5
        vm.toggleDay(0)
        vm.toggleDay(4)

        let result = vm.save()
        XCTAssertTrue(result)

        let alarms = repo.fetchAllOrFail()
        XCTAssertEqual(alarms.count, 1)

        let saved = alarms.first!
        XCTAssertEqual(saved.name, "Утренний")
        XCTAssertEqual(saved.penaltyAmount, 100)
        XCTAssertEqual(saved.snoozeMinutes, 5)
        XCTAssertEqual(saved.repeatDays, [0, 4])
    }

    func testSave_emptyNameDefaultsToPlaceholder() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.name = ""
        vm.save()

        let saved = repo.fetchAllOrFail().first
        XCTAssertEqual(saved?.name, "Будильник")
        // The editor reads `Alarm.defaultName` rather than its own literal
        // (#598): one default, one place to change it. Since #623 an empty
        // field stores NO name at all and the default is resolved on display,
        // so the alarm keeps reading as default-named after a translation
        // ships instead of freezing today's Russian word into storage.
        XCTAssertEqual(saved?.name, Alarm.defaultName)
        XCTAssertEqual(saved?.nameIsDefault, true)
        XCTAssertNil(saved?.customName)
    }

    /// Opening a default-named alarm in the editor must not silently turn its
    /// default into a typed name: the field seeds empty (placeholder visible),
    /// and saving without touching it leaves the alarm on the default (#623).
    /// Echoing "Будильник" into the field would make the alarms list start
    /// printing "БУДИЛЬНИК · …" for an alarm the user merely opened.
    func testEdit_defaultNamedAlarm_seedsEmptyFieldAndStaysDefault() {
        let original = Alarm(repeatDays: [0], penaltyAmount: 50)
        repo.save(original)

        let vm = CreateAlarmViewModel(alarm: original, repository: repo)
        XCTAssertEqual(vm.name, "", "A default name is not something the user typed")

        vm.penaltyAmount = 120
        vm.save()

        let saved = repo.fetchAllOrFail().first
        XCTAssertEqual(saved?.penaltyAmount, 120)
        XCTAssertEqual(saved?.nameIsDefault, true)
        XCTAssertEqual(saved?.name, Alarm.defaultName)
    }

    func testEdit_namedAlarm_keepsTheNameUserOwned() {
        let original = Alarm(repeatDays: [0], name: "Спорт", penaltyAmount: 50)
        repo.save(original)

        let vm = CreateAlarmViewModel(alarm: original, repository: repo)
        XCTAssertEqual(vm.name, "Спорт")

        vm.save()

        let saved = repo.fetchAllOrFail().first
        XCTAssertEqual(saved?.name, "Спорт")
        XCTAssertEqual(saved?.nameIsDefault, false)
    }

    func testSave_editExistingAlarm() {
        // Create an alarm first
        let original = Alarm(name: "Оригинал", penaltyAmount: 50)
        repo.save(original)
        XCTAssertEqual(repo.fetchAllOrFail().count, 1)

        // Edit it
        let vm = CreateAlarmViewModel(alarm: original, repository: repo)
        XCTAssertTrue(vm.isEditing)
        vm.name = "Изменённый"
        vm.penaltyAmount = 200
        vm.save()

        // Should still be 1 alarm, updated
        let alarms = repo.fetchAllOrFail()
        XCTAssertEqual(alarms.count, 1)
        XCTAssertEqual(alarms.first?.name, "Изменённый")
        XCTAssertEqual(alarms.first?.penaltyAmount, 200)
    }

    // MARK: - Delete (issue #50)

    func testDelete_existingAlarm_removesFromRepository() {
        // Persist an alarm directly so the VM thinks it's editing an existing one.
        let original = Alarm(name: "Утро", penaltyAmount: 100)
        repo.save(original)
        XCTAssertEqual(repo.fetchAllOrFail().count, 1)

        let vm = CreateAlarmViewModel(alarm: original, repository: repo)
        XCTAssertTrue(vm.isEditing)

        let didDelete = vm.delete()
        XCTAssertTrue(didDelete)
        XCTAssertEqual(repo.fetchAllOrFail().count, 0)
    }

    func testDelete_newAlarm_isNoOp() {
        // No existingID → there's nothing to delete. The VM should refuse and
        // return false so the VC can short-circuit (no alert dismiss, etc.).
        let vm = CreateAlarmViewModel(repository: repo)
        XCTAssertFalse(vm.isEditing)

        let didDelete = vm.delete()
        XCTAssertFalse(didDelete)
        XCTAssertEqual(repo.fetchAllOrFail().count, 0)
    }

    func testDelete_existingAlarm_doesNotAffectOtherAlarms() {
        // Two alarms, delete one — the other must survive.
        let alpha = Alarm(name: "Альфа")
        let beta = Alarm(name: "Бета")
        repo.save(alpha)
        repo.save(beta)
        XCTAssertEqual(repo.fetchAllOrFail().count, 2)

        let vm = CreateAlarmViewModel(alarm: alpha, repository: repo)
        vm.delete()

        let remaining = repo.fetchAllOrFail()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.name, "Бета")
    }

    func testInit_fromExistingAlarm_loadsValues() {
        let alarm = Alarm(
            repeatDays: [0, 2, 4],
            name: "Работа",
            soundID: "radar",
            vibrationEnabled: false,
            snoozeMinutes: 15,
            penaltyAmount: 200,
            progressiveScale: true,
            enabled: false
        )
        let vm = CreateAlarmViewModel(alarm: alarm, repository: repo)

        XCTAssertTrue(vm.isEditing)
        XCTAssertEqual(vm.name, "Работа")
        XCTAssertEqual(vm.soundID, "radar")
        XCTAssertFalse(vm.vibrationEnabled)
        XCTAssertEqual(vm.snoozeMinutes, 15)
        XCTAssertEqual(vm.penaltyAmount, 200)
        XCTAssertTrue(vm.progressiveScale)
        XCTAssertFalse(vm.enabled)
        XCTAssertEqual(vm.repeatDays, [0, 2, 4])
    }

    // MARK: - Progressive chain from a custom price (#230)

    func testProgressiveChain_recomputesFromCustomPenalty() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 75
        // Free-input price feeds the ×2 ladder: [base, ×2, ×4, ×8].
        XCTAssertEqual(vm.progressiveChain, [75, 150, 300, 600])
    }

    func testProgressiveChain_defaultPriceLadder() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 50
        XCTAssertEqual(vm.progressiveChain, [50, 100, 200, 400])
    }

    func testProgressiveChain_nonFinitePenaltyDegradesToDefault() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = .nan
        XCTAssertEqual(vm.progressiveChain, [50, 100, 200, 400])
    }

    // MARK: - Editable price cell floor (#230)

    func testPenaltyCell_minimumIsOneRouble() {
        XCTAssertEqual(PenaltyCell.minimumAmount, 1)
    }
}
