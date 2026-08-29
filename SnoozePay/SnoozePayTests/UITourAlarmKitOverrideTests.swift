import XCTest
@testable import SnoozePay

/// `-uitour-alarmkit granted|denied` — the seam that gives the E2E run an
/// alarm backend it can state, instead of whatever the simulator happened to
/// answer (#606).
///
/// Three things are worth pinning, and they are the three ways this can go
/// wrong silently:
///
/// 1. **Spelling.** The flag lives in `CreateAlarmUITests.launchArguments` as a
///    string literal — a UI test cannot import the app module. A typo on
///    either side hands that test straight back to ambient authorization,
///    which is exactly the failure #606 exists to close.
/// 2. **Opt-in.** No flag (or an unknown value) must leave the real backend
///    alone. A DEBUG build that faked authorization by default would tell a
///    human running the app by hand that alarms are armed when they are not.
/// 3. **Isolation.** The override must reach `AlarmScheduler.shared` — the
///    instance the app actually saves through — and must NOT reach a scheduler
///    that was handed its own backend, or a leak from one test would decide
///    another test's outcome.
final class UITourAlarmKitOverrideTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AlarmScheduler.uiTourForcedBackend = nil
    }

    override func tearDown() {
        // The singleton outlives the test case, so a leaked override would be
        // inherited by every test that runs after this one.
        AlarmScheduler.uiTourForcedBackend = nil
        super.tearDown()
    }

    private func makeAlarm() -> Alarm {
        Alarm(repeatDays: [0, 1, 2, 3, 4], name: "Работа", penaltyAmount: 50)
    }

    private func scheduleOutcome(
        on scheduler: AlarmScheduler
    ) -> Result<Void, AlarmScheduler.SchedulingError>? {
        let exp = expectation(description: "schedule completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(makeAlarm()) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        return captured
    }

    // MARK: - Spelling

    func testArgumentSpelling_matchesTheUITestLaunchArguments() {
        XCTAssertEqual(
            UITourLauncher.alarmKitArgument,
            "-uitour-alarmkit",
            "spelling is contract with CreateAlarmUITests.launchArguments — change both or neither"
        )
    }

    // MARK: - Parsing

    func testForcedBackend_isNilWithoutTheFlag() {
        XCTAssertNil(
            UITourLauncher.forcedAlarmKitBackend(arguments: []),
            "no arguments must leave the real AlarmKit backend in place"
        )
        XCTAssertNil(
            UITourLauncher.forcedAlarmKitBackend(
                arguments: ["-uitour", "create", "-uitour-reset"]
            ),
            "the other -uitour flags must not imply an authorization decision"
        )
    }

    func testForcedBackend_isNilForAnUnknownValue() {
        XCTAssertNil(
            UITourLauncher.forcedAlarmKitBackend(
                arguments: [UITourLauncher.alarmKitArgument, "maybe"]
            ),
            "an unrecognised state must refuse to guess rather than fake a grant"
        )
        XCTAssertNil(
            UITourLauncher.forcedAlarmKitBackend(
                arguments: ["-uitour", "create", UITourLauncher.alarmKitArgument]
            ),
            "a flag with no value trailing it must parse as absent, not as granted"
        )
    }

    func testForcedBackend_granted_reportsAuthorized() {
        let backend = UITourLauncher.forcedAlarmKitBackend(
            arguments: ["-uitour", "create", UITourLauncher.alarmKitArgument, "granted"]
        )
        XCTAssertEqual(backend?.authorization, .authorized)
        XCTAssertEqual(backend?.isAuthorized, true)
    }

    func testForcedBackend_denied_reportsDeniedNotNotDetermined() {
        let backend = UITourLauncher.forcedAlarmKitBackend(
            arguments: [UITourLauncher.alarmKitArgument, "denied"]
        )
        // `.denied` and not `.notDetermined`: the decision is already made, so
        // an in-app prompt that could still resolve it would be a lie — the
        // permissions screen picks its CTA off this value.
        XCTAssertEqual(backend?.authorization, .denied)
        XCTAssertEqual(backend?.isAuthorized, false)
    }

    func testForcedBackend_neverPrompts() {
        let backend = UITourLauncher.forcedAlarmKitBackend(
            arguments: [UITourLauncher.alarmKitArgument, "granted"]
        )
        var granted: Bool?
        backend?.requestAuthorization { granted = $0 }
        XCTAssertEqual(
            granted, true,
            "authorization must resolve from the pinned decision — a system dialog would flake the E2E"
        )
    }

    // MARK: - Wiring into the shared scheduler

    /// The half the green E2E depends on: a granted override makes the
    /// singleton the app saves through arm alarms.
    func testGrantedOverride_makesSharedSchedulerArmAlarms() {
        AlarmScheduler.uiTourForcedBackend = UITourAlarmKitBackend(isAuthorized: true)

        XCTAssertTrue(AlarmScheduler.shared.usesAlarmKit)
        XCTAssertEqual(AlarmScheduler.shared.alarmKitAuthorization, .authorized)
        guard case .success = scheduleOutcome(on: .shared) else {
            return XCTFail("A granted tour backend must let the save path arm the alarm")
        }
    }

    /// The half that keeps the #472 contract testable: a denied override
    /// refuses, with the typed error the create form turns into an alert.
    func testDeniedOverride_makesSharedSchedulerRefuse() {
        AlarmScheduler.uiTourForcedBackend = UITourAlarmKitBackend(isAuthorized: false)

        XCTAssertFalse(AlarmScheduler.shared.usesAlarmKit)
        XCTAssertEqual(AlarmScheduler.shared.alarmKitAuthorization, .denied)
        guard case .failure(.backendUnavailable) = scheduleOutcome(on: .shared) else {
            return XCTFail("A denied tour backend must refuse with .backendUnavailable")
        }
    }

    // MARK: - Isolation

    func testOverride_doesNotHijackASchedulerThatWiredItsOwnBackend() {
        AlarmScheduler.uiTourForcedBackend = UITourAlarmKitBackend(isAuthorized: false)
        let scheduler = AlarmScheduler(
            notificationCenter: InertNotificationCenter(),
            alarmKit: TestAlarmKitBackend()
        )

        XCTAssertTrue(
            scheduler.usesAlarmKit,
            "an explicitly injected backend must win over a tour override"
        )
        guard case .success = scheduleOutcome(on: scheduler) else {
            return XCTFail("The injected backend decides the outcome, not the override")
        }
    }

    func testOverride_doesNotConjureABackendForASchedulerThatHasNone() {
        AlarmScheduler.uiTourForcedBackend = UITourAlarmKitBackend(isAuthorized: true)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)

        XCTAssertFalse(
            scheduler.usesAlarmKit,
            "'no backend wired' is a state tests exercise deliberately — the override must not fill it"
        )
        guard case .failure(.backendUnavailable) = scheduleOutcome(on: scheduler) else {
            return XCTFail("A scheduler with no backend must still refuse")
        }
    }

    func testClearingTheOverride_restoresTheRealBackend() {
        // Whatever the machine really answers — unauthorized on a CI
        // simulator, possibly authorized on a granted device. Asserting
        // against the captured value instead of a hard-coded one keeps this
        // test about stickiness rather than about the runner.
        let realState = AlarmScheduler.shared.usesAlarmKit

        AlarmScheduler.uiTourForcedBackend = UITourAlarmKitBackend(isAuthorized: !realState)
        XCTAssertEqual(AlarmScheduler.shared.usesAlarmKit, !realState,
                       "the override must actually take effect on the singleton")

        AlarmScheduler.uiTourForcedBackend = nil
        XCTAssertEqual(AlarmScheduler.shared.usesAlarmKit, realState,
                       "clearing the override must hand the scheduler back to the real AlarmKit state")
    }
}
