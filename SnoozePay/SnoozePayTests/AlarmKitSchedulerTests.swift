import XCTest
import UserNotifications
import AlarmKit
@testable import SnoozePay

// `import AlarmKit` brings `AlarmKit.Alarm` into scope, which collides with the
// app's `SnoozePay.Alarm` model. We need both: the AlarmKit `Schedule` /
// `Recurrence` enums for pattern-matching the mapping output, and the app model
// to build test fixtures. `AppAlarm` disambiguates the app model so every
// fixture / mock signature is unambiguous.
private typealias AppAlarm = SnoozePay.Alarm

/// Unit tests for the AlarmKit (Strategy A) integration in `AlarmScheduler`
/// (#377). Covers the iOS-26-vs-notification-fallback branching through the
/// injectable `AlarmKitScheduling` seam, plus the `Alarm` → AlarmKit config
/// mapping. The branching tests run on any host because they exercise the
/// `AlarmScheduling` API; the config-mapping tests are gated to iOS 26.
final class AlarmKitSchedulerTests: XCTestCase {

    // MARK: - Branching: schedule routes to the right backend

    /// When AlarmKit is authorized (Strategy A), `schedule` must hand the alarm
    /// to the AlarmKit backend and NOT register any notification request.
    func testSchedule_authorizedAlarmKit_routesToAlarmKitNotNotifications() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)

        let exp = expectation(description: "schedule completes")
        scheduler.schedule(AppAlarm(penaltyAmount: 50)) { result in
            if case .failure = result { XCTFail("expected success on AlarmKit path") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(alarmKit.scheduledIDs.count, 1,
                       "Authorized AlarmKit must receive the schedule call")
        XCTAssertTrue(center.addedRequests.isEmpty,
                      "Strategy A must not also register a notification (Strategy B)")
    }

    /// When AlarmKit is present but NOT authorized, `schedule` must fall back to
    /// the notification path so the user is never left without an alarm.
    func testSchedule_unauthorizedAlarmKit_fallsBackToNotifications() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: false)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)

        let exp = expectation(description: "schedule completes")
        scheduler.schedule(AppAlarm(penaltyAmount: 50)) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(alarmKit.scheduledIDs.isEmpty,
                      "Unauthorized AlarmKit must not be used")
        XCTAssertFalse(center.addedRequests.isEmpty,
                       "Fallback must register at least one notification (Strategy B)")
    }

    /// With no AlarmKit backend wired (the pre-#377 / iOS < 26 shape), behaviour
    /// is unchanged: the alarm is scheduled via notifications.
    func testSchedule_noAlarmKitBackend_usesNotificationFallback() {
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: nil)

        let exp = expectation(description: "schedule completes")
        scheduler.schedule(AppAlarm(penaltyAmount: 50)) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertFalse(center.addedRequests.isEmpty,
                       "Without AlarmKit the notification fallback must still schedule")
    }

    /// A disabled alarm short-circuits on every backend — no AlarmKit schedule,
    /// no notification add.
    func testSchedule_disabledAlarm_isNoOpOnBothBackends() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)

        let exp = expectation(description: "schedule completes")
        scheduler.schedule(AppAlarm(penaltyAmount: 50, enabled: false)) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(alarmKit.scheduledIDs.isEmpty)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    /// #417: when the AlarmKit PRIMARY schedule fails to land asynchronously
    /// (alarm limit, revoked auth, backend reject), `AlarmScheduler.schedule`
    /// MUST NOT report a phantom success — it must arm the notification fallback
    /// so the user (who was told "Будильник создан") still has an alarm. The old
    /// fire-and-log path swallowed this and left nothing armed.
    func testSchedule_alarmKitAsyncFailure_armsNotificationFallback() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true, failSchedule: true)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)
        let alarm = AppAlarm(penaltyAmount: 50)

        let exp = expectation(description: "schedule completes")
        // The completion must fire exactly once (over-fulfillment = a double
        // report from both the AlarmKit branch and the fallback).
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        var reportedResult: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(alarm) { result in
            reportedResult = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(alarmKit.scheduledIDs, [alarm.id],
                       "AlarmKit schedule must have been attempted before failing over")
        XCTAssertFalse(center.addedRequests.isEmpty,
                       "On async AlarmKit failure the notification fallback MUST be armed")
        // Result is reported ONLY after the async failure resolves into the
        // fallback. With the notification fallback landed, success is correct:
        // an alarm exists. The regression we guard against is success with NO
        // notification armed (covered by the addedRequests assertion).
        if case .failure = reportedResult {
            XCTFail("With the notification fallback armed the schedule should report success")
        }
    }

    /// Worst case for #417: AlarmKit async-rejects AND the notification fallback's
    /// `add` also errors. The user was told nothing yet, so the result MUST be a
    /// typed `.failure` — never a phantom success that leaves no alarm armed.
    func testSchedule_bothBackendsFail_reportsFailureNotPhantomSuccess() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true, failSchedule: true)
        let center = RecordingCenter()
        center.failAdds = true
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)
        let alarm = AppAlarm(penaltyAmount: 50)

        let exp = expectation(description: "schedule completes")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        var reportedResult: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(alarm) { result in
            reportedResult = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .failure = reportedResult else {
            XCTFail("When BOTH AlarmKit and the notification fallback fail, the "
                + "schedule must report a typed .failure, not phantom success")
            return
        }
    }

    // MARK: - Snooze routing (#383)

    /// On the AlarmKit path a snooze must reschedule a real system alarm (NOT a
    /// notification) and must stop the currently-alerting alarm *before*
    /// rescheduling, so the ringing stops and the snooze re-arms cleanly.
    func testScheduleSnooze_authorizedAlarmKit_stopsThenReschedulesViaAlarmKit() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)
        let alarm = AppAlarm(penaltyAmount: 50)

        let exp = expectation(description: "snooze completes")
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { result in
            if case .failure = result { XCTFail("expected success on AlarmKit snooze path") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(alarmKit.snoozedIDs, [alarm.id],
                       "Authorized AlarmKit must receive the snooze reschedule")
        XCTAssertEqual(alarmKit.stoppedIDs, [alarm.id],
                       "The currently-alerting alarm must be stopped on snooze")
        XCTAssertEqual(alarmKit.callLog, ["stop", "scheduleSnooze"],
                       "Stop must run BEFORE the reschedule so the alarm stops ringing")
        XCTAssertTrue(center.addedRequests.isEmpty,
                      "Strategy A snooze must not also register a notification (Strategy B)")
    }

    /// The AlarmKit snooze re-fire date is now + the alarm's snoozeMinutes.
    func testScheduleSnooze_authorizedAlarmKit_fireDateIsNowPlusSnoozeMinutes() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: alarmKit)
        let alarm = AppAlarm(snoozeMinutes: 9, penaltyAmount: 50)

        let before = Date()
        let exp = expectation(description: "snooze completes")
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
        let after = Date()

        let fireDate = try XCTUnwrap(alarmKit.snoozeFireDates.first)
        XCTAssertGreaterThanOrEqual(fireDate.timeIntervalSince(before), 9 * 60 - 1)
        XCTAssertLessThanOrEqual(fireDate.timeIntervalSince(after), 9 * 60 + 1)
    }

    /// On the notification fallback (AlarmKit unauthorized) the snooze stays a
    /// notification (Strategy B) — the existing behaviour must not regress.
    func testScheduleSnooze_unauthorizedAlarmKit_fallsBackToNotification() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: false)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)

        let exp = expectation(description: "snooze completes")
        scheduler.scheduleSnooze(for: AppAlarm(penaltyAmount: 50), snoozeCount: 1) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(alarmKit.snoozedIDs.isEmpty, "Unauthorized AlarmKit must not reschedule a system snooze")
        XCTAssertFalse(center.addedRequests.isEmpty, "Fallback must register the notification snooze")
    }

    /// With no AlarmKit backend (iOS < 26 shape) the snooze is a notification —
    /// the pre-#383 behaviour, unchanged.
    func testScheduleSnooze_noAlarmKitBackend_usesNotificationFallback() {
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: nil)

        let exp = expectation(description: "snooze completes")
        scheduler.scheduleSnooze(for: AppAlarm(penaltyAmount: 50), snoozeCount: 1) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertFalse(center.addedRequests.isEmpty,
                       "Without AlarmKit the notification snooze fallback must still register")
    }

    /// #394 Finding 1: when the AlarmKit system snooze fails to schedule
    /// asynchronously (alarm limit, revoked auth, backend reject), the caller
    /// MUST arm the notification-burst fallback so a re-ring still exists — the
    /// penalty was already charged and the original already stopped, so a
    /// swallowed failure would leave the user with nothing ringing.
    func testScheduleSnooze_alarmKitAsyncFailure_armsNotificationFallback() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true, failSnooze: true)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)
        let alarm = AppAlarm(penaltyAmount: 50)

        let exp = expectation(description: "snooze completes")
        var reportedResult: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { result in
            reportedResult = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(alarmKit.snoozedIDs, [alarm.id],
                       "AlarmKit snooze must have been attempted before failing over")
        XCTAssertFalse(center.addedRequests.isEmpty,
                       "On async AlarmKit failure the notification re-ring fallback MUST be armed")
        if case .success = reportedResult {
            // Fallback notification landed → reporting success is correct: a
            // re-ring exists. The regression we guard against is success with
            // NO notification armed (covered by the addedRequests assertion).
        } else {
            XCTFail("With the notification fallback armed the snooze should report success")
        }
    }

    // MARK: - Past-date floor (#394 Finding 2)

    /// `.fixed` with a past instant silently never fires. A `fireDate` captured
    /// before the async schedule await can land in the past under latency; the
    /// floor must bump it strictly forward instead of passing the past instant
    /// straight through.
    func testMakeSnoozeSchedule_pastFireDate_isFlooredForward() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let now = Date()
        // A fireDate already in the past (latency ate the snooze gap).
        let pastDate = now.addingTimeInterval(-30)
        let floored = AlarmKitScheduler.flooredSnoozeFireDate(pastDate, now: now)

        XCTAssertGreaterThan(floored, now,
                             "A past fireDate must be bumped strictly into the future, not passed through")
        XCTAssertEqual(floored.timeIntervalSince(now),
                       AlarmKitScheduler.pastDateFloorBuffer, accuracy: 0.001,
                       "Floored snooze must land exactly at now + buffer")
    }

    /// A comfortably-future fireDate is passed through unchanged — the floor only
    /// engages when latency would otherwise push `.fixed` into the past.
    func testMakeSnoozeSchedule_futureFireDate_isUnchanged() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let now = Date()
        let future = now.addingTimeInterval(9 * 60)
        XCTAssertEqual(AlarmKitScheduler.flooredSnoozeFireDate(future, now: now), future,
                       "A future fireDate must not be altered by the floor")

        // And the public schedule entry point yields a .fixed at that instant.
        guard case let .fixed(date) = AlarmKitScheduler.makeSnoozeSchedule(fireDate: future) else {
            return XCTFail("Snooze must use an absolute .fixed schedule")
        }
        XCTAssertEqual(date.timeIntervalSince(future), 0, accuracy: 1)
    }

    // MARK: - Cancel + stop forward to AlarmKit

    func testCancel_forwardsToAlarmKitBackend() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: alarmKit)
        let id = UUID()

        scheduler.cancel(id)

        XCTAssertEqual(alarmKit.cancelledIDs, [id],
                       "cancel(_:) must also cancel the AlarmKit system alarm")
    }

    func testStopSystemAlarm_forwardsToAlarmKitBackend() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: alarmKit)
        let id = UUID()

        scheduler.stopSystemAlarm(id)

        XCTAssertEqual(alarmKit.stoppedIDs, [id])
    }

    func testStopSystemAlarm_noBackend_isNoOp() {
        // No crash when no AlarmKit backend exists (iOS < 26 / fallback shape).
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: nil)
        scheduler.stopSystemAlarm(UUID())
    }

    // MARK: - Authorization request

    func testRequestAlarmKitAuthorization_forwardsGrant() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: alarmKit)

        let exp = expectation(description: "authorization resolves")
        scheduler.requestAlarmKitAuthorization { granted in
            XCTAssertTrue(granted)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(alarmKit.authorizationRequests, 1)
    }

    func testRequestAlarmKitAuthorization_noBackend_completesFalse() {
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: nil)
        let exp = expectation(description: "completes")
        scheduler.requestAlarmKitAuthorization { granted in
            XCTAssertFalse(granted, "No backend → cannot be authorized")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Config mapping (iOS 26 only)

    func testMakeSchedule_weeklyAlarm_mapsRepeatDaysToWeekdays() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        // Monday (0) + Sunday (6) selected, weekly mode.
        let alarm = AppAlarm(repeatDays: [0, 6], penaltyAmount: 50, repeatMode: .weekly)
        let schedule = AlarmKitScheduler.makeSchedule(for: alarm)

        guard case let .relative(relative) = schedule,
              case let .weekly(days) = relative.repeats else {
            return XCTFail("Weekly alarm must map to a relative weekly schedule")
        }
        XCTAssertTrue(days.contains(.monday))
        XCTAssertTrue(days.contains(.sunday))
        XCTAssertEqual(days.count, 2)
    }

    func testMakeSchedule_oneShotAlarm_usesNeverRecurrence() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let alarm = AppAlarm(repeatDays: [], penaltyAmount: 50)
        let schedule = AlarmKitScheduler.makeSchedule(for: alarm)

        guard case let .relative(relative) = schedule,
              case .never = relative.repeats else {
            return XCTFail("One-shot alarm must use .never recurrence")
        }
    }

    // MARK: - Snooze schedule + id (#394)

    /// The snooze schedule must be an ABSOLUTE `.fixed` schedule pinned to the
    /// exact fireDate — NOT a relative hh:mm schedule that drops seconds and can
    /// roll over to the next day. Regression guard for the ~24h drift (#394).
    func testMakeSnoozeSchedule_usesFixedAbsoluteDate_notRelative() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        // Far-future instant with non-zero seconds (2100-01-01 00:00:30 UTC): it is
        // well beyond `now + floor buffer`, so the past-date floor (#394 Finding 2)
        // does NOT engage and `.fixed` must echo the exact fireDate, proving seconds
        // are preserved (not truncated to hh:mm).
        let fireDate = Date(timeIntervalSince1970: 4_102_444_830)
        let schedule = AlarmKitScheduler.makeSnoozeSchedule(fireDate: fireDate)

        guard case let .fixed(date) = schedule else {
            return XCTFail("Snooze must use an absolute .fixed schedule, not .relative")
        }
        XCTAssertEqual(date, fireDate,
                       "The snooze must fire at the exact fireDate, seconds preserved")
    }

    /// A short snooze planned at a non-zero-seconds instant must fire ≈ now + N,
    /// never ~24h later. Exercises the boundary the relative-schedule bug failed:
    /// 07:00:30 + 1min = 07:01:30, which a seconds-truncating relative schedule
    /// would round to 07:01 (already past) and push to tomorrow (#394).
    func testMakeSnoozeSchedule_shortSnoozeFiresWithinTheMinute_notNextDay() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let now = Date()
        let fireDate = now.addingTimeInterval(60) // +1 minute
        let schedule = AlarmKitScheduler.makeSnoozeSchedule(fireDate: fireDate)

        guard case let .fixed(date) = schedule else {
            return XCTFail("Snooze must use an absolute .fixed schedule")
        }
        let delta = date.timeIntervalSince(now)
        XCTAssertEqual(delta, 60, accuracy: 1,
                       "Snooze must fire ~1 min out, not ~24h (86400s) later")
        XCTAssertLessThan(delta, 3600, "A snooze must never land hours/days away")
    }

    /// The snooze is scheduled under a SEPARATE id derived from the alarm id, so
    /// a `.weekly` original is never overwritten by the one-shot snooze and keeps
    /// ringing on its weekdays (#394). The derived id must be stable and distinct.
    func testSnoozeID_isDistinctFromAlarmIDButDeterministic() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let alarmID = UUID()
        let snoozeID = AlarmKitScheduler.snoozeID(for: alarmID)

        XCTAssertNotEqual(snoozeID, alarmID,
                          "Snooze must use a different id so the weekly original survives")
        XCTAssertEqual(snoozeID, AlarmKitScheduler.snoozeID(for: alarmID),
                       "Derivation must be deterministic — same alarm → same snooze id")
        // Distinct alarms map to distinct snooze ids (no collisions).
        XCTAssertNotEqual(AlarmKitScheduler.snoozeID(for: alarmID),
                          AlarmKitScheduler.snoozeID(for: UUID()))
    }

    /// End-to-end mapping guard for #394 part 1: a weekly alarm's MAIN schedule
    /// (`makeSchedule`) still carries its weekly recurrence — the snooze path
    /// (which targets the separate snooze id) cannot touch it. The original
    /// alarm keeps ringing on its configured weekdays after a snooze.
    func testWeeklyAlarm_mainScheduleKeepsRecurrence_independentOfSnooze() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let alarm = AppAlarm(repeatDays: [0, 2, 4], penaltyAmount: 50, repeatMode: .weekly)
        // Snooze targets a different id, so the alarm's own schedule is untouched.
        XCTAssertNotEqual(AlarmKitScheduler.snoozeID(for: alarm.id), alarm.id)

        guard case let .relative(relative) = AlarmKitScheduler.makeSchedule(for: alarm),
              case let .weekly(days) = relative.repeats else {
            return XCTFail("Weekly alarm must keep its weekly recurrence")
        }
        XCTAssertEqual(Set(days), [.monday, .wednesday, .friday])
    }

    func testWeekdayMapping_coversAllSevenIndices() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let expected: [Int: Locale.Weekday] = [
            0: .monday, 1: .tuesday, 2: .wednesday, 3: .thursday,
            4: .friday, 5: .saturday, 6: .sunday
        ]
        for (index, weekday) in expected {
            XCTAssertEqual(AlarmKitScheduler.weekday(forMondayFirstIndex: index), weekday)
        }
        XCTAssertNil(AlarmKitScheduler.weekday(forMondayFirstIndex: 7),
                     "Out-of-range index is dropped, not crashed")
    }

    // MARK: - Deallocated-during-async-reject (#424, #417 follow-up)

    /// Issue #424: `schedule`'s AlarmKit branch captures `[weak self]`; if the
    /// scheduler is torn down between dispatching the async AlarmKit schedule and
    /// its rejection callback, the `guard let self else` arm must report a typed
    /// `.failure(.cancelled)` — never a phantom success and never a hang. The
    /// synchronous `MockAlarmKitScheduler` can't cover this (it answers while the
    /// scheduler is still alive); this deferring double releases the callback on
    /// demand so the test can drop the scheduler first.
    func testSchedule_deallocatedAfterAsyncReject_reportsCancelled() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = DeferringAlarmKitScheduler(authorized: true)
        let center = RecordingCenter()
        var scheduler: AlarmScheduler? = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)
        let alarm = AppAlarm(penaltyAmount: 50)

        let exp = expectation(description: "schedule reports cancelled")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        var reported: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler?.schedule(alarm) { result in
            reported = result
            exp.fulfill()
        }

        // AlarmKit captured the completion but hasn't answered. The scheduler's
        // only strong reference is ours (the mock holds the [weak self] closure,
        // which does not retain it) — drop it so the guard sees nil.
        XCTAssertNotNil(alarmKit.pendingCompletion,
                        "AlarmKit schedule must be awaiting its async result")
        XCTAssertNil(reported, "No result before the async reject resolves")
        scheduler = nil

        // Now fire the async rejection. With self deallocated the guard must
        // report .cancelled (not arm a fallback, not hang, not phantom-succeed).
        alarmKit.fireRejection()
        wait(for: [exp], timeout: 2.0)

        guard case .failure(.cancelled) = reported else {
            return XCTFail("Deallocated-after-async-reject must report .cancelled, "
                + "got \(String(describing: reported))")
        }
        XCTAssertTrue(center.addedRequests.isEmpty,
                      "A deallocated scheduler must not arm a notification fallback")
    }
}

// MARK: - Test doubles

/// Records the calls `AlarmScheduler` makes against its AlarmKit seam so the
/// Strategy-A-vs-fallback branching can be asserted on any host OS. Mirrors the
/// `PermissionStubCenter` pattern from `AlarmSchedulerTests`.
private final class MockAlarmKitScheduler: AlarmKitScheduling {
    struct SnoozeScheduleError: Error {}
    struct ScheduleError: Error {}

    private let authorized: Bool
    /// When `true`, `scheduleSnooze` reports `.failure` via its completion (after
    /// still recording the call) — models an async AlarmKit reject so the caller
    /// must arm the notification fallback instead (#394 Finding 1).
    private let failSnooze: Bool
    /// When `true`, `schedule` reports `.failure` via its completion (after still
    /// recording the call) — models an async AlarmKit reject on the PRIMARY
    /// schedule path so the caller must arm the notification fallback instead of
    /// reporting a phantom success (#417).
    private let failSchedule: Bool
    private(set) var scheduledIDs: [UUID] = []
    private(set) var snoozedIDs: [UUID] = []
    private(set) var snoozeFireDates: [Date] = []
    private(set) var cancelledIDs: [UUID] = []
    private(set) var stoppedIDs: [UUID] = []
    private(set) var authorizationRequests = 0
    /// Ordered log of every mutating call so #383 can assert the snooze stops
    /// the alerting alarm BEFORE rescheduling.
    private(set) var callLog: [String] = []

    init(authorized: Bool, failSnooze: Bool = false, failSchedule: Bool = false) {
        self.authorized = authorized
        self.failSnooze = failSnooze
        self.failSchedule = failSchedule
    }

    var isAuthorized: Bool { authorized }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        authorizationRequests += 1
        completion(authorized)
    }

    func schedule(
        _ alarm: AppAlarm,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        scheduledIDs.append(alarm.id)
        callLog.append("schedule")
        completion(failSchedule ? .failure(ScheduleError()) : .success(()))
    }

    func scheduleSnooze(
        _ alarm: AppAlarm,
        fireDate: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        snoozedIDs.append(alarm.id)
        snoozeFireDates.append(fireDate)
        callLog.append("scheduleSnooze")
        completion(failSnooze ? .failure(SnoozeScheduleError()) : .success(()))
    }

    func cancel(_ alarmID: UUID) {
        cancelledIDs.append(alarmID)
        callLog.append("cancel")
    }

    func stop(_ alarmID: UUID) {
        stoppedIDs.append(alarmID)
        callLog.append("stop")
    }
}

/// `AlarmKitScheduling` double that DEFERS its `schedule` completion: it stores
/// the callback and only invokes it (as a `.failure`) when `fireRejection()` is
/// called. Lets a test drop the `AlarmScheduler` reference before the async
/// reject lands, exercising the deallocated-scheduler `.cancelled` guard (#424).
private final class DeferringAlarmKitScheduler: AlarmKitScheduling {
    struct ScheduleRejected: Error {}

    private let authorized: Bool
    private(set) var scheduledIDs: [UUID] = []
    /// The captured schedule completion, awaiting `fireRejection()`.
    var pendingCompletion: ((Result<Void, Error>) -> Void)?

    init(authorized: Bool) { self.authorized = authorized }

    var isAuthorized: Bool { authorized }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        completion(authorized)
    }

    func schedule(
        _ alarm: AppAlarm,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        scheduledIDs.append(alarm.id)
        pendingCompletion = completion
    }

    /// Resolve the deferred schedule with a rejection — models AlarmKit
    /// async-rejecting after the scheduler may already be gone.
    func fireRejection() {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(.failure(ScheduleRejected()))
    }

    func scheduleSnooze(
        _ alarm: AppAlarm,
        fireDate: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {}
    func cancel(_ alarmID: UUID) {}
    func stop(_ alarmID: UUID) {}
}

/// `NotificationScheduling` double that records every `add` so the fallback
/// path can be observed. Completes async members with empty results so the
/// pre-flight 64-pending check resolves deterministically.
private final class RecordingCenter: NotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []
    /// When true, every `add` reports an error so the notification fallback
    /// itself fails — used to exercise the both-backends-fail path (#417).
    var failAdds = false

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: ((Error?) -> Void)?
    ) {
        addedRequests.append(request)
        completion?(failAdds ? NSError(domain: "RecordingCenterTest", code: 1) : nil)
    }
    func getPendingNotificationRequests(
        completionHandler: @escaping ([UNNotificationRequest]) -> Void
    ) {
        completionHandler([])
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func getDeliveredNotifications(
        completionHandler: @escaping ([UNNotification]) -> Void
    ) {
        completionHandler([])
    }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func removeAllPendingNotificationRequests() {}
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        completionHandler(true, nil)
    }
}
