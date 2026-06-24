import XCTest
@testable import SnoozePay

/// Unit tests for the #379 routing surface: AlarmKit alert buttons and the
/// foreground `alarmUpdates` observer both funnel an alarm-open into our custom
/// firing screen via an injectable presentation seam — verified here without a
/// live `AlarmManager` / UIKit hierarchy.
@MainActor
final class AlarmKitFiringRoutingTests: XCTestCase {

    // MARK: - AlarmKitActionRouter

    /// Stop button presents the firing screen for the alarm's id.
    func testRouterStop_presentsFiringScreenForAlarmID() {
        let router = AlarmKitActionRouter()
        var presented: [UUID] = []
        router.present = { presented.append($0) }
        let id = UUID()

        router.handleStop(alarmIDString: id.uuidString)

        XCTAssertEqual(presented, [id],
                       "Stop must route the alarm-open to our firing screen")
    }

    /// Snooze button presents the firing screen for the alarm's id (the paid
    /// snooze itself runs in-app, not from the lock-screen button).
    func testRouterSnooze_presentsFiringScreenForAlarmID() async {
        let router = AlarmKitActionRouter()
        var presented: [UUID] = []
        router.present = { presented.append($0) }
        let id = UUID()

        await router.handleSnooze(alarmIDString: id.uuidString)

        XCTAssertEqual(presented, [id],
                       "Snooze must route the alarm-open to our firing screen")
    }

    /// A malformed alarmID is rejected without presenting anything.
    func testRouterStop_malformedID_doesNotPresent() {
        let router = AlarmKitActionRouter()
        var presented: [UUID] = []
        router.present = { presented.append($0) }

        router.handleStop(alarmIDString: "not-a-uuid")

        XCTAssertTrue(presented.isEmpty, "Malformed id must not present a screen")
    }

    func testRouterSnooze_malformedID_doesNotPresent() async {
        let router = AlarmKitActionRouter()
        var presented: [UUID] = []
        router.present = { presented.append($0) }

        await router.handleSnooze(alarmIDString: "")

        XCTAssertTrue(presented.isEmpty, "Malformed id must not present a screen")
    }

    // MARK: - AlarmKitAlertObserver dedup

    /// A newly-alerting alarm presents exactly once even though the stream
    /// re-emits the same snapshot on every state change.
    func testObserver_presentsEachAlertingAlarmOnce() {
        var presented: [UUID] = []
        let observer = AlarmKitAlertObserver(stream: nil, onAlerting: { presented.append($0) })
        let alarmA = UUID()

        observer.handle(alertingIDs: [alarmA])
        observer.handle(alertingIDs: [alarmA]) // repeated snapshot
        observer.handle(alertingIDs: [alarmA])

        XCTAssertEqual(presented, [alarmA],
                       "A still-alerting alarm must not re-present on repeated snapshots")
    }

    /// An alarm that stops alerting and later fires again presents twice.
    func testObserver_reFiringAfterStop_presentsAgain() {
        var presented: [UUID] = []
        let observer = AlarmKitAlertObserver(stream: nil, onAlerting: { presented.append($0) })
        let alarmA = UUID()

        observer.handle(alertingIDs: [alarmA]) // first fire
        observer.handle(alertingIDs: [])       // stopped
        observer.handle(alertingIDs: [alarmA]) // re-fire

        XCTAssertEqual(presented, [alarmA, alarmA],
                       "Re-firing after the alarm stopped must present again")
    }

    /// Multiple simultaneously-alerting alarms each present once.
    func testObserver_multipleAlerting_presentEachOnce() {
        var presented: Set<UUID> = []
        let observer = AlarmKitAlertObserver(stream: nil, onAlerting: { presented.insert($0) })
        let alarmA = UUID()
        let alarmB = UUID()

        observer.handle(alertingIDs: [alarmA, alarmB])
        observer.handle(alertingIDs: [alarmA, alarmB])

        XCTAssertEqual(presented, [alarmA, alarmB])
    }

    /// An empty alerting set presents nothing.
    func testObserver_emptySet_presentsNothing() {
        var presentedCount = 0
        let observer = AlarmKitAlertObserver(stream: nil, onAlerting: { _ in presentedCount += 1 })

        observer.handle(alertingIDs: [])

        XCTAssertEqual(presentedCount, 0)
    }
}
