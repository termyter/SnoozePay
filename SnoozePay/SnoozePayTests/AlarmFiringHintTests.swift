import XCTest
@testable import SnoozePay

/// Tests for the firing screen's snooze-cost hint copy (#274). Once the
/// progressive ladder caps at `base × 8` the hint stops quoting a higher
/// "next price" and shows the max-step copy instead. The hint helper reads
/// only `viewModel`, which is built in the VC initializer, so we can exercise
/// it without loading the view hierarchy.
final class AlarmFiringHintTests: XCTestCase {

    private func makeAlarm(penalty: Double, progressive: Bool) -> Alarm {
        Alarm(penaltyAmount: penalty, progressiveScale: progressive)
    }

    func testSnoozeHint_nilWhenNotProgressive() {
        let vc = AlarmFiringViewController(
            alarm: makeAlarm(penalty: 50, progressive: false),
            snoozeCount: 0
        )
        XCTAssertNil(vc.snoozeHintText(),
                     "Flat penalty alarms get no escalating-cost hint")
    }

    func testSnoozeHint_showsNextPriceBeforeCeiling() {
        // snoozeCount=0 → probes penalty(forSnoozeCount: 2) = 100.
        let vc = AlarmFiringViewController(
            alarm: makeAlarm(penalty: 50, progressive: true),
            snoozeCount: 0
        )
        XCTAssertEqual(vc.snoozeHintText(),
                       "Следующее откладывание: \(MoneyFormatter.string(100))")
    }

    func testSnoozeHint_showsNextPriceAtThirdRung() {
        // snoozeCount=1 → probes penalty(forSnoozeCount: 3) = 200 (still below ceiling).
        let vc = AlarmFiringViewController(
            alarm: makeAlarm(penalty: 50, progressive: true),
            snoozeCount: 1
        )
        XCTAssertEqual(vc.snoozeHintText(),
                       "Следующее откладывание: \(MoneyFormatter.string(200))")
    }

    func testSnoozeHint_showsMaxCopyAtCeiling() {
        // snoozeCount=2 → probes penalty(forSnoozeCount: 4), which is the
        // base × 8 ceiling. No higher price to show → max-step copy.
        let vc = AlarmFiringViewController(
            alarm: makeAlarm(penalty: 50, progressive: true),
            snoozeCount: 2
        )
        XCTAssertEqual(vc.snoozeHintText(), "максимум — дальше только встать")
    }

    func testSnoozeHint_staysMaxCopyBeyondCeiling() {
        let vc = AlarmFiringViewController(
            alarm: makeAlarm(penalty: 50, progressive: true),
            snoozeCount: 8
        )
        XCTAssertEqual(vc.snoozeHintText(), "максимум — дальше только встать")
    }
}
