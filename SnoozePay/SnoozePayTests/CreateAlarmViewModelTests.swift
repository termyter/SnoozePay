import XCTest
@testable import SnoozePay

/// Unit tests for CreateAlarmViewModel — sound preview, defaults, day toggle, progressive scale.
final class CreateAlarmViewModelSoundTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "test.createAlarm.\(UUID().uuidString)")!
        repo = AlarmRepository(defaults: testDefaults)
    }

    override func tearDown() {
        if let name = testDefaults.suiteName {
            UserDefaults.removePersistentDomain(forName: name)
        }
        super.tearDown()
    }

    // MARK: - Available sounds

    func testAvailableSounds_hasCorrectCount() {
        let vm = CreateAlarmViewModel(repository: repo)
        XCTAssertEqual(vm.availableSounds.count, 6)
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
        vm.previewSound("default")
        vm.previewSound("radar")
        vm.previewSound("chimes")
    }

    func testPreviewSound_withInvalidID_doesNotCrash() {
        let vm = CreateAlarmViewModel(repository: repo)
        // Invalid IDs should be silently ignored (guard let returns)
        vm.previewSound("nonexistent_sound")
        vm.previewSound("")
        vm.previewSound("🎵")
    }

    // MARK: - Default values

    func testDefaultValues_areCorrect() {
        let vm = CreateAlarmViewModel(repository: repo)

        XCTAssertEqual(vm.name, "Будильник")
        XCTAssertEqual(vm.penaltyAmount, 50)
        XCTAssertEqual(vm.snoozeMinutes, 9)
        XCTAssertEqual(vm.soundID, "default")
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

    // MARK: - Progressive scale preview

    func testProgressiveScalePreview_format() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 50
        let preview = vm.progressiveScalePreview
        XCTAssertEqual(preview, "1-е: 50₽ → 2-е: 100₽ → 3-е: 200₽ → 4-е: 400₽")
    }

    func testProgressiveScalePreview_withHighPenalty() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 1000
        let preview = vm.progressiveScalePreview
        XCTAssertEqual(preview, "1-е: 1000₽ → 2-е: 2000₽ → 3-е: 4000₽ → 4-е: 8000₽")
    }

    func testProgressiveScalePreview_withMinimumPenalty() {
        let vm = CreateAlarmViewModel(repository: repo)
        vm.penaltyAmount = 10
        let preview = vm.progressiveScalePreview
        XCTAssertTrue(preview.hasPrefix("1-е: 10₽"))
        XCTAssertTrue(preview.contains("2-е: 20₽"))
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

        let alarms = repo.fetchAll()
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

        let saved = repo.fetchAll().first
        XCTAssertEqual(saved?.name, "Будильник")
    }

    func testSave_editExistingAlarm() {
        // Create an alarm first
        let original = Alarm(name: "Оригинал", penaltyAmount: 50)
        repo.save(original)
        XCTAssertEqual(repo.fetchAll().count, 1)

        // Edit it
        let vm = CreateAlarmViewModel(alarm: original, repository: repo)
        XCTAssertTrue(vm.isEditing)
        vm.name = "Изменённый"
        vm.penaltyAmount = 200
        vm.save()

        // Should still be 1 alarm, updated
        let alarms = repo.fetchAll()
        XCTAssertEqual(alarms.count, 1)
        XCTAssertEqual(alarms.first?.name, "Изменённый")
        XCTAssertEqual(alarms.first?.penaltyAmount, 200)
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
}
