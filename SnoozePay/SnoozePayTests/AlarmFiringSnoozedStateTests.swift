import XCTest
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
    // The next ring anchors to the snooze-TAP moment (`reference`), not the
    // alarm's time-of-day × snoozeCount (issue #396). This mirrors
    // `AlarmScheduler.scheduledFireDate`, which registers the snooze trigger at
    // `now + snoozeMinutes` regardless of `snoozeCount`. So the next-ring time is
    // always `reference + snoozeMinutes` — independent of how many snoozes have
    // accrued or how long after the alarm the user finally tapped snooze.

    func testNextRingTime_firstSnooze_shiftsByOneIntervalFromTap() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 5), snoozeCount: 1)
        // Tapped at 07:01 → next ring 07:06 (tap + 5min), NOT 07:05 (alarm + 5).
        let text = vm.nextRingTimeText(after: reference(hour: 7, minute: 1))
        XCTAssertEqual(text, "07:06", "07:01 tap + 5min = 07:06")
    }

    func testNextRingTime_thirdSnooze_stillOneIntervalFromTap() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 5), snoozeCount: 3)
        // The interval does not accumulate with snoozeCount — each tap re-anchors.
        let text = vm.nextRingTimeText(after: reference(hour: 7, minute: 11))
        XCTAssertEqual(text, "07:16", "07:11 tap + 5min = 07:16, regardless of snoozeCount")
    }

    func testNextRingTime_customInterval() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 9), snoozeCount: 2)
        let text = vm.nextRingTimeText(after: reference(hour: 7, minute: 10))
        XCTAssertEqual(text, "07:19", "07:10 tap + 9min = 07:19")
    }

    func testSnoozedHeroTitle_includesNameAndNextRing() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 5), snoozeCount: 1)
        let title = vm.snoozedHeroTitle(after: reference(hour: 7, minute: 1))
        XCTAssertEqual(title, "Будни · отложено до 07:06")
    }

    func testSnoozedHeroTitle_blankNameDropsSeparator() {
        let alarm = makeAlarm(snoozeMinutes: 5)
        let renamed = alarm.with(name: "   ")
        let vm = AlarmFiringViewModel(alarm: renamed, snoozeCount: 1)
        let title = vm.snoozedHeroTitle(after: reference(hour: 7, minute: 1))
        XCTAssertEqual(title, "отложено до 07:06", "Whitespace name must not leave a dangling «·»")
    }

    // MARK: - Countdown

    func testSecondsUntilNextRing_countsRemainder() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 5), snoozeCount: 1)
        // Tapped at 07:00:00; next ring tap + 5min = 07:05:00 → 300s.
        let now = reference(hour: 7, minute: 0)
        XCTAssertEqual(vm.secondsUntilNextRing(from: now), 300)
    }

    /// Issue #396 regression: snoozing well AFTER the alarm rang must still yield
    /// a positive countdown ≈ snoozeMinutes. Under the old time-of-day anchoring a
    /// 07:00 alarm snoozed at 07:12 pointed at the long-past 07:05 → clamped to 0,
    /// so the snoozed chrome never installed and the countdown was dead.
    func testSecondsUntilNextRing_lateSnooze_isPositiveOneInterval() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 5), snoozeCount: 1)
        // Alarm fired 07:00, user dawdles, taps snooze at 07:12.
        let tap = reference(hour: 7, minute: 12)
        let seconds = vm.secondsUntilNextRing(from: tap)
        XCTAssertEqual(seconds, 5 * 60, "Late snooze still counts a full interval from the tap")
        XCTAssertGreaterThan(seconds, 0, "Snoozed chrome must install — countdown is positive")
    }

    func testSecondsUntilNextRing_clampsAtZeroPastRing() {
        let vm = AlarmFiringViewModel(alarm: makeAlarm(snoozeMinutes: 5), snoozeCount: 1)
        // 6 minutes after the 07:00 tap — past the tap + 5min ring; never negative.
        let now = reference(hour: 7, minute: 0).addingTimeInterval(6 * 60)
        XCTAssertEqual(vm.secondsUntilNextRing(from: now), 0)
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
}
