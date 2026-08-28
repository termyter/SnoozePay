import XCTest
import UserNotifications
@testable import SnoozePay

/// Coverage for the snoozed firing state (#226) — the pure VM logic that drives
/// the "отложено" chrome: next-ring time, the 4-rung charge ladder, and the
/// countdown formatting. UIKit-free so it runs without a view hierarchy.
final class AlarmFiringSnoozedStateTests: XCTestCase {

    // MARK: - Helpers

    /// Build an alarm whose time is a fixed 07:00 on a known calendar day so the
    /// next-ring maths is deterministic regardless of the test machine's clock.
    private func makeAlarm(
        penalty: Double = 50,
        progressive: Bool = false,
        snoozeMinutes: Int = 5
    ) -> Alarm {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 27
        components.hour = 7
        components.minute = 0
        let time = Calendar.current.date(from: components) ?? Date()
        return Alarm(
            time: time,
            name: "Будни",
            snoozeMinutes: snoozeMinutes,
            penaltyAmount: penalty,
            progressiveScale: progressive
        )
    }

    /// A reference "now" of 07:01 on the alarm's day — one minute after the ring.
    private func reference(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 27
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Next-ring time
    //
    // The next ring anchors to the FIXED snooze-TAP moment (`snoozeAnchor`), not
    // the alarm's time-of-day × snoozeCount (issue #396). This mirrors
    // `AlarmScheduler.scheduledFireDate`, which arms the snooze trigger at
    // `tap + snoozeMinutes` regardless of `snoozeCount`. So the next-ring time is
    // always `anchor + snoozeMinutes` — independent of how many snoozes have
    // accrued or how long after the alarm the user finally tapped snooze.

    func testNextRingTime_firstSnooze_shiftsByOneIntervalFromTap() {
        // Tapped at 07:01 → next ring 07:06 (tap + 5min), NOT 07:05 (alarm + 5).
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            snoozeCount: 1,
            snoozeAnchor: reference(hour: 7, minute: 1)
        )
        XCTAssertEqual(vm.nextRingTimeText(), "07:06", "07:01 tap + 5min = 07:06")
    }

    func testNextRingTime_thirdSnooze_stillOneIntervalFromTap() {
        // The interval does not accumulate with snoozeCount — each tap re-anchors.
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            snoozeCount: 3,
            snoozeAnchor: reference(hour: 7, minute: 11)
        )
        XCTAssertEqual(vm.nextRingTimeText(), "07:16", "07:11 tap + 5min = 07:16, regardless of snoozeCount")
    }

    func testNextRingTime_customInterval() {
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 9),
            snoozeCount: 2,
            snoozeAnchor: reference(hour: 7, minute: 10)
        )
        XCTAssertEqual(vm.nextRingTimeText(), "07:19", "07:10 tap + 9min = 07:19")
    }

    func testNextRingTime_noAnchor_isEmpty() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 5), snoozeCount: 0)
        XCTAssertEqual(vm.nextRingTimeText(), "", "Before the first snooze there is no anchored ring")
        XCTAssertNil(vm.nextRingDate(), "No anchor → no target date")
    }

    func testSnoozedHeroTitle_includesNameAndNextRing() {
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            snoozeCount: 1,
            snoozeAnchor: reference(hour: 7, minute: 1)
        )
        XCTAssertEqual(vm.snoozedHeroTitle(), "Будни · отложено до 07:06")
    }

    func testSnoozedHeroTitle_blankNameDropsSeparator() {
        let alarm = makeAlarm(snoozeMinutes: 5).with(name: "   ")
        let vm = AlarmFiringViewModel(
            alarm: alarm,
            snoozeCount: 1,
            snoozeAnchor: reference(hour: 7, minute: 1)
        )
        XCTAssertEqual(vm.snoozedHeroTitle(), "отложено до 07:06", "Whitespace name must not leave a dangling «·»")
    }

    // MARK: - Countdown
    //
    // The countdown subtracts the MOVING `now` from the FIXED target
    // (`snoozeAnchor + snoozeMinutes`), so it decrements every tick and reaches
    // `0` at the re-ring (issue #396). The previous attempt computed the target
    // from the per-call `now`, freezing the countdown at a constant.

    func testSecondsUntilNextRing_atTap_isFullInterval() {
        // Anchor 07:00, query at the same instant → the full 5-min interval.
        let anchor = reference(hour: 7, minute: 0)
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            snoozeCount: 1,
            snoozeAnchor: anchor
        )
        XCTAssertEqual(vm.secondsUntilNextRing(from: anchor), 300)
    }

    /// The countdown must actually TICK DOWN as `now` advances against the fixed
    /// target — the regression the previous attempt introduced (constant 300s).
    func testSecondsUntilNextRing_decrementsAsNowAdvances() {
        let anchor = reference(hour: 7, minute: 0)
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            snoozeCount: 1,
            snoozeAnchor: anchor
        )
        // Anchor 07:00, target 07:05. now=07:01 → 240s, now=07:04 → 60s.
        XCTAssertEqual(vm.secondsUntilNextRing(from: anchor.addingTimeInterval(60)), 240)
        XCTAssertEqual(vm.secondsUntilNextRing(from: anchor.addingTimeInterval(4 * 60)), 60)
        XCTAssertGreaterThan(
            vm.secondsUntilNextRing(from: anchor.addingTimeInterval(60)),
            vm.secondsUntilNextRing(from: anchor.addingTimeInterval(4 * 60)),
            "A later now must yield fewer remaining seconds — the countdown decrements"
        )
    }

    /// Issue #396 regression: snoozing well AFTER the alarm rang must still yield
    /// a positive countdown that then ticks to 0. Under the old time-of-day
    /// anchoring a 07:00 alarm snoozed at 07:12 pointed at the long-past 07:05 →
    /// clamped to 0, so the snoozed chrome never installed and the countdown was
    /// dead. With the tap anchor the target is 07:17 and the countdown is live.
    func testSecondsUntilNextRing_lateSnooze_isPositiveThenReachesZero() {
        // Alarm fired 07:00, user dawdles, taps snooze at 07:12.
        let tap = reference(hour: 7, minute: 12)
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            snoozeCount: 1,
            snoozeAnchor: tap
        )
        // At the tap the chrome installs (positive countdown to 07:17).
        XCTAssertEqual(vm.secondsUntilNextRing(from: tap), 5 * 60,
                       "Late snooze still counts a full interval from the tap")
        XCTAssertEqual(vm.nextRingTimeText(), "07:17", "07:12 tap + 5min = 07:17")
        // Six minutes later (07:18) the target has passed → countdown is 0, so the
        // ticker fires `exitSnoozedState()`.
        XCTAssertEqual(vm.secondsUntilNextRing(from: tap.addingTimeInterval(6 * 60)), 0,
                       "Past the target the live countdown reaches 0 — exitSnoozedState fires")
    }

    func testSecondsUntilNextRing_clampsAtZeroPastRing() {
        let anchor = reference(hour: 7, minute: 0)
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            snoozeCount: 1,
            snoozeAnchor: anchor
        )
        // 6 minutes after the 07:00 tap — past the tap + 5min ring; never negative.
        XCTAssertEqual(vm.secondsUntilNextRing(from: anchor.addingTimeInterval(6 * 60)), 0)
    }

    func testSecondsUntilNextRing_noAnchor_isZero() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 5), snoozeCount: 0)
        XCTAssertEqual(vm.secondsUntilNextRing(from: Date()), 0,
                       "No snooze taken → no countdown, so the snoozed chrome never installs")
    }

    func testCountdownText_formatsMinutesSeconds() {
        XCTAssertEqual(AlarmFiringViewModel.countdownText(seconds: 263), "04:23")
        XCTAssertEqual(AlarmFiringViewModel.countdownText(seconds: 5), "00:05")
        XCTAssertEqual(AlarmFiringViewModel.countdownText(seconds: 0), "00:00")
    }

    func testCountdownText_clampsNegative() {
        XCTAssertEqual(AlarmFiringViewModel.countdownText(seconds: -10), "00:00")
    }

    // MARK: - Charge ladder

    func testLadderSteps_emptyWhenNotProgressive() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(progressive: false), snoozeCount: 2)
        XCTAssertTrue(vm.ladderSteps.isEmpty, "Non-progressive alarms hide the ladder")
    }

    func testLadderSteps_amountsAreDoublingSchedule() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(penalty: 50, progressive: true), snoozeCount: 1)
        XCTAssertEqual(vm.ladderSteps.map { $0.amount }, [50, 100, 200, 400])
    }

    func testLadderSteps_stateAfterFirstSnooze() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(penalty: 50, progressive: true), snoozeCount: 1)
        XCTAssertEqual(
            vm.ladderSteps.map { $0.state },
            [.done, .current, .future, .future],
            "After 1 snooze, rung 0 is paid, rung 1 is the current rung"
        )
    }

    func testLadderSteps_stateAtStart() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(penalty: 50, progressive: true), snoozeCount: 0)
        XCTAssertEqual(vm.ladderSteps.map { $0.state }, [.current, .future, .future, .future])
    }

    func testLadderSteps_clampsCurrentAtCeiling() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(penalty: 50, progressive: true), snoozeCount: 6)
        XCTAssertEqual(
            vm.ladderSteps.map { $0.state },
            [.done, .done, .done, .current],
            "Past the last rung, current clamps to rung 4 so the ladder never blanks"
        )
    }

    // MARK: - Last charge (fly-up amount)

    func testLastChargeAmount_zeroBeforeSnooze() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(penalty: 50, progressive: true), snoozeCount: 0)
        XCTAssertEqual(vm.lastChargeAmount, 0)
    }

    func testLastChargeAmount_progressiveTracksRung() {
        // snoozeCount == 2 → most recent charge was rung 2 = base × 2 = 100.
        let vm = AlarmFiringViewModel(alarm: makeAlarm(penalty: 50, progressive: true), snoozeCount: 2)
        XCTAssertEqual(vm.lastChargeAmount, 100)
    }

    func testLastChargeAmount_flatWhenNotProgressive() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(penalty: 50, progressive: false), snoozeCount: 3)
        XCTAssertEqual(vm.lastChargeAmount, 50, "Flat penalty alarms charge the base each time")
    }

    // MARK: - Stored tap anchor (#396)
    //
    // `snooze()` must pin the anchor ONCE at the tap so the countdown target is
    // fixed (decrementing countdown). Re-tapping snooze must re-anchor to the new
    // tap — matching the freshly-armed scheduler trigger.

    func testSnooze_setsAnchorAndProducesLiveCountdown() {
        let billing = SnoozedStubBalance(balanceValue: 1000)
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            balanceService: billing,
            scheduler: AlarmScheduler(notificationCenter: SilentNotificationCenter())
        )
        XCTAssertNil(vm.snoozeAnchor, "No anchor before the first snooze")

        let before = Date()
        XCTAssertTrue(vm.snooze())
        let after = Date()

        let anchor = try? XCTUnwrap(vm.snoozeAnchor)
        XCTAssertNotNil(anchor, "snooze() pins the tap moment")
        if let anchor {
            XCTAssertGreaterThanOrEqual(anchor.timeIntervalSince1970, before.timeIntervalSince1970)
            XCTAssertLessThanOrEqual(anchor.timeIntervalSince1970, after.timeIntervalSince1970)
            // Countdown measured from the fixed target ticks down toward 0.
            let atTap = vm.secondsUntilNextRing(from: anchor)
            let later = vm.secondsUntilNextRing(from: anchor.addingTimeInterval(120))
            XCTAssertEqual(atTap, 300)
            XCTAssertEqual(later, 180, "Countdown decrements as now advances against the fixed target")
        }
    }

    func testSnooze_reTapReAnchorsToLatestTap() {
        let billing = SnoozedStubBalance(balanceValue: 1000)
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(snoozeMinutes: 5),
            balanceService: billing,
            scheduler: AlarmScheduler(notificationCenter: SilentNotificationCenter())
        )
        XCTAssertTrue(vm.snooze())
        let firstAnchor = vm.snoozeAnchor
        // Second snooze re-anchors — its target is a fresh interval from the new tap.
        XCTAssertTrue(vm.snooze())
        let secondAnchor = vm.snoozeAnchor
        XCTAssertNotNil(firstAnchor)
        XCTAssertNotNil(secondAnchor)
        if let first = firstAnchor, let second = secondAnchor {
            XCTAssertGreaterThanOrEqual(second.timeIntervalSince1970, first.timeIntervalSince1970,
                                        "Re-tapping snooze re-anchors to the later tap moment")
        }
    }

    // MARK: - No-balance / countdown mutual exclusion (#398)
    //
    // When a snooze drains the wallet below the next penalty the firing screen
    // must show EITHER the live countdown OR the "Баланса не осталось" stack,
    // never both. The VC fold hides the no-balance stack while the snoozed chrome
    // is up; this VM-level test guarantees the precondition the fold relies on —
    // a draining snooze still yields a positive countdown so the chrome installs
    // (which is what triggers hiding the no-balance stack).

    func testSnooze_draining_stillYieldsPositiveCountdown_soChromeOwnsScreen() {
        // Wallet covers exactly one 50₽ snooze, then goes empty.
        let billing = SnoozedStubBalance(balanceValue: 50)
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50, snoozeMinutes: 5),
            balanceService: billing,
            scheduler: AlarmScheduler(notificationCenter: SilentNotificationCenter())
        )
        XCTAssertTrue(vm.canSnooze, "Pre-snooze the wallet covers the penalty")

        XCTAssertTrue(vm.snooze())

        // Post-snooze the wallet is empty → the no-balance state would normally show.
        XCTAssertFalse(vm.canSnooze, "Snooze drained the wallet below the next penalty")
        // …but the snooze ALSO armed a live countdown, so the snoozed chrome
        // installs and (per the fold) hides the no-balance stack: exactly one of
        // the two is on screen, never both.
        let anchor = vm.snoozeAnchor
        XCTAssertNotNil(anchor)
        if let anchor {
            XCTAssertGreaterThan(vm.secondsUntilNextRing(from: anchor), 0,
                                 "A draining snooze still installs the countdown chrome, which owns the screen")
        }
    }
}

// MARK: - Test doubles

/// Minimal `AlarmFiringBalancing` for the snoozed-state tests — charges drain a
/// running balance so a snooze can flip `canSnooze` to `false` (the #398
/// drain-to-empty scenario) without touching `UserDefaults`.
private final class SnoozedStubBalance: AlarmFiringBalancing {
    private(set) var balance: Double
    init(balanceValue: Double) { balance = balanceValue }

    func canAfford(_ amount: Double) -> Bool { balance >= amount }

    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        guard balance >= amount else { return nil }
        balance -= amount
        return Transaction(type: .charge, amount: amount, alarmID: alarmID?.uuidString)
    }

    @discardableResult
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool {
        balance += amount
        return true
    }
}

/// `NotificationScheduling` stub that accepts every `add` so `scheduleSnooze`
/// resolves successfully — the snoozed-state tests only care about the VM's
/// anchor/countdown maths, not the trigger registration.
private final class SilentNotificationCenter: NotificationScheduling {
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: ((Error?) -> Void)?
    ) {
        completion?(nil)
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
