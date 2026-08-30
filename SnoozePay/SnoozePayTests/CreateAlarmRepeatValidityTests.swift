import XCTest
@testable import SnoozePay

/// #633 — the create form used to open in a state it could not honour
/// («Еженедельно» + zero days) and then save a DIFFERENT mode (one-shot)
/// without saying so. Two halves are pinned here:
///
///  1. **The opening state is savable as shown.** Saving a freshly opened form
///     without touching anything produces the alarm the screen described.
///  2. **The mismatch can no longer happen quietly.** «Еженедельно» with zero
///     days is a refusal with a reason, not a silent downgrade — and
///     «Еженедельно» with days round-trips as weekly.
///
/// The refusal is enforced in the view-model rather than only in the
/// controller on purpose: the dimmed «Готово» button is what the user sees,
/// but a view-model that persists whatever it is handed would bring the bug
/// back the first time a call site forgets to refresh the button.
final class CreateAlarmRepeatValidityTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.repeatValidity.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Opening state

    func testNewForm_opensValid_withOneShotModeAndNoDays() {
        let viewModel = CreateAlarmViewModel(repository: repo)

        XCTAssertTrue(viewModel.repeatDays.isEmpty)
        XCTAssertEqual(viewModel.repeatMode, .never,
                       "A form with no days selected must not open on «Еженедельно» — "
                           + "that combination cannot be saved as shown")
        XCTAssertTrue(viewModel.canSave, "The opening state must be savable")
        XCTAssertNil(viewModel.validationError)
    }

    /// The exact reproduction from the issue: open, touch nothing, tap «Готово».
    /// What lands in the store must be the mode the pill was showing.
    func testNewForm_savedWithoutAnyInteraction_persistsTheModeItDisplayed() {
        let viewModel = CreateAlarmViewModel(repository: repo)
        let displayedMode = viewModel.repeatMode

        XCTAssertTrue(viewModel.save())

        let saved = repo.fetchAllOrFail().first
        XCTAssertEqual(saved?.repeatMode, displayedMode)
        XCTAssertEqual(saved?.repeatDays, [])
    }

    func testNewForm_hintDescribesTheOneShotItWouldSave() {
        let viewModel = CreateAlarmViewModel(repository: repo)

        XCTAssertEqual(viewModel.repeatModeHint,
                       "Будильник сработает один раз и отключится.",
                       "The opening hint must not promise repetition «по выбранным дням» "
                           + "when no day is selected")
    }

    /// A weekly alarm with zero days was only ever reachable through the old
    /// form; it has always RUNG once (`AlarmKitScheduler.makeSchedule` builds
    /// `.never` recurrence for it, and the list row reads «ЕДИНОЖДЫ»). Opening
    /// it shows that truth instead of re-displaying the contradiction.
    func testEditingLegacyWeeklyAlarmWithoutDays_opensAsOneShot() {
        let legacy = Alarm(repeatDays: [], repeatMode: .weekly)

        let viewModel = CreateAlarmViewModel(alarm: legacy, repository: repo)

        XCTAssertEqual(viewModel.repeatMode, .never)
        XCTAssertTrue(viewModel.canSave)
    }

    func testEditingWeeklyAlarmWithDays_keepsItsOwnMode() {
        let alarm = Alarm(repeatDays: [0, 4], repeatMode: .weekly)

        let viewModel = CreateAlarmViewModel(alarm: alarm, repository: repo)

        XCTAssertEqual(viewModel.repeatMode, .weekly)
        XCTAssertEqual(viewModel.repeatDays, [0, 4])
    }

    // MARK: - Weekly is saved as weekly

    func testWeeklySelection_withDays_roundTripsAsWeekly() {
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.toggleDay(1)
        viewModel.toggleDay(3)
        viewModel.repeatMode = .weekly

        XCTAssertTrue(viewModel.canSave)
        XCTAssertTrue(viewModel.save())

        let saved = repo.fetchAllOrFail().first
        XCTAssertEqual(saved?.repeatMode, .weekly,
                       "The user picked «Еженедельно» — that is what must be stored")
        XCTAssertEqual(saved?.repeatDays, [1, 3])
    }

    // MARK: - Weekly without days is refused, not downgraded

    func testWeeklyWithoutDays_isInvalid() {
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.repeatMode = .weekly

        XCTAssertEqual(viewModel.validationError, .weeklyWithoutDays)
        XCTAssertFalse(viewModel.canSave)
    }

    func testWeeklyWithoutDays_savesNothing() {
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.repeatMode = .weekly

        XCTAssertFalse(viewModel.save(), "An unsavable form must report that nothing was saved")
        XCTAssertTrue(repo.fetchAllOrFail().isEmpty,
                      "The old behaviour wrote a one-shot alarm here — the mode the user "
                          + "did NOT pick")
    }

    /// The async overload the screen actually uses. Its refusal short-circuits
    /// before the repository, so the outcome arrives on the calling thread —
    /// no expectation needed, and asserting it that way pins that the store is
    /// never reached.
    func testWeeklyWithoutDays_asyncSaveReportsTheReasonWithoutTouchingTheStore() {
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.repeatMode = .weekly

        var outcome: CreateAlarmViewModel.SaveOutcome?
        viewModel.save { outcome = $0 }

        XCTAssertEqual(outcome, CreateAlarmViewModel.SaveOutcome.invalid(.weeklyWithoutDays))
        XCTAssertTrue(repo.fetchAllOrFail().isEmpty)
    }

    func testWeeklyWithoutDays_hintExplainsInsteadOfPromisingRepetition() {
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.repeatMode = .weekly

        XCTAssertEqual(viewModel.repeatModeHint,
                       "Выберите хотя бы один день недели — иначе повторять нечего.")
        XCTAssertEqual(viewModel.repeatModeHint,
                       CreateAlarmViewModel.ValidationError.weeklyWithoutDays.message,
                       "The hint and the refusal must give the same reason")
    }

    /// The state is reachable in the middle of editing too: pick weekly, then
    /// clear the chips. It must go invalid there rather than at save time.
    func testUnselectingTheLastDayUnderWeekly_makesTheFormInvalid() {
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.toggleDay(2)
        viewModel.repeatMode = .weekly
        XCTAssertTrue(viewModel.canSave)

        viewModel.toggleDay(2)

        XCTAssertEqual(viewModel.validationError, .weeklyWithoutDays)
        XCTAssertFalse(viewModel.canSave)
    }

    func testSelectingADayClearsTheRefusal() {
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.repeatMode = .weekly
        XCTAssertFalse(viewModel.canSave)

        viewModel.toggleDay(5)

        XCTAssertTrue(viewModel.canSave)
        XCTAssertEqual(viewModel.repeatModeHint, "Будет повторяться каждую неделю по выбранным дням.")
    }

    // MARK: - The seeding rule itself

    func testOpeningRepeatMode_mapsDaylessWeeklyToOneShotAndPassesEverythingElseThrough() {
        XCTAssertEqual(CreateAlarmViewModel.openingRepeatMode(stored: .weekly, days: []), .never)
        XCTAssertEqual(CreateAlarmViewModel.openingRepeatMode(stored: .never, days: []), .never)
        XCTAssertEqual(CreateAlarmViewModel.openingRepeatMode(stored: .weekly, days: [0]), .weekly)
        XCTAssertEqual(CreateAlarmViewModel.openingRepeatMode(stored: .never, days: [0]), .never)
    }
}
