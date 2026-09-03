#if DEBUG
import Foundation

/// DEBUG-only AlarmKit stand-in for the `-uitour-alarmkit granted|denied`
/// launch argument (#606).
///
/// Why a stub instead of a real grant: AlarmKit authorization cannot be set on
/// a simulator. There is no `simctl privacy` service for alarms, the tour
/// routes never reach `PermissionsViewController` (they mount a screen
/// directly), and an in-test system prompt would be a timing race on the
/// SpringBoard alert. So the E2E run gets the authorization it needs the same
/// way `AlarmBackendMonitor.uiTourForcedAvailability` (#545) gets the "alarms
/// won't ring" state: pinned explicitly at the seam, rather than hoped for
/// from the environment.
///
/// What that buys is a test that says what it means. `granted` asserts the
/// app's own save → schedule → dismiss → row-in-list wiring on a backend that
/// arms; `denied` asserts the #472 contract that a refused schedule keeps the
/// sheet up and explains itself. Neither depends on the ambient (and
/// unsettable) authorization state of the CI simulator.
///
/// Deliberately NOT a general-purpose spy: recording call counts would invite
/// UI tests to assert on them, and a UI test cannot read this object anyway.
final class UITourAlarmKitBackend: AlarmKitScheduling {

    /// Reported by every authorization surface, and the reason
    /// `AlarmScheduler.schedule` either arms or refuses with
    /// `.backendUnavailable`.
    let isAuthorized: Bool

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
    }

    /// Tri-state mirror of `isAuthorized`. `.denied` rather than
    /// `.notDetermined` for the refusing case: the tour has already decided,
    /// so an in-app prompt that could still resolve would be a lie —
    /// `SystemAlarmBackendProbe` reads this to pick between prompting and
    /// pointing at Settings.
    var authorization: AlarmKitAuthorization { isAuthorized ? .authorized : .denied }

    /// Answers with the pinned decision instead of prompting. The tour must
    /// never put a system dialog on screen — an unexpected SpringBoard alert
    /// is what makes UI tests flaky.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        completion(isAuthorized)
    }

    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(result())
    }

    func scheduleSnooze(
        _ alarm: Alarm,
        fireDate: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(result())
    }

    func cancel(_ alarmID: UUID) {}

    func stop(_ alarmID: UUID) {}

    /// A denied backend never reaches these calls in practice —
    /// `AlarmScheduler` refuses on `usesAlarmKit` first — but failing here too
    /// keeps the double honest if that guard ever moves.
    private func result() -> Result<Void, Error> {
        isAuthorized ? .success(()) : .failure(NotAuthorized())
    }

    /// Stands in for the error a real AlarmKit refusal would carry.
    ///
    /// # Its text stays a Swift literal (#598)
    ///
    /// `AlarmScheduler.SchedulingError.system(message:)` substitutes this into
    /// `alarms.error.schedule_failed` *unchanged*, because on the real backend
    /// `message` arrives already localized by the OS — the catalogue owns the
    /// sentence around it, never the message itself. This double is that
    /// message's stand-in, so it takes the same treatment.
    ///
    /// It is also unreachable on the path that would put it on screen:
    /// `AlarmScheduler.schedule` checks authorization first and refuses a
    /// denied backend with `.backendUnavailable`, which *is* catalogue-backed
    /// (`alarms.error.backend_unavailable`).
    /// `UITourAlarmKitOverrideTests.testDeniedOverride_makesSharedSchedulerRefuse`
    /// pins exactly that, so this decision goes red if the guard ever moves.
    ///
    /// The «(UI-тур)» tag is the point of the string: it tells whoever meets it
    /// that the failure is fabricated. That is a DEBUG diagnostic, and there is
    /// nothing for a translator to do with it.
    struct NotAuthorized: LocalizedError {
        var errorDescription: String? { "AlarmKit не авторизован (UI-тур)" }
    }
}
#endif
