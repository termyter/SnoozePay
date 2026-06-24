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

    // MARK: - AlarmFiringPresenter pending-present (#382)

    /// Builds a presenter with injectable readiness + mount seams so the
    /// pending-present logic is exercised without a UIKit window.
    private func makePresenter(
        rootReady: @escaping () -> Bool,
        mounted: @escaping (UUID) -> Bool
    ) -> AlarmFiringPresenter {
        let presenter = AlarmFiringPresenter(alarmRepository: .shared)
        presenter.isRootReady = rootReady
        presenter.mount = { alarmID, _ in mounted(alarmID) }
        return presenter
    }

    /// When no window is ready yet, a request records the alarm as pending and
    /// mounts nothing — the screen must survive until the scene becomes active.
    func testPresenter_requestBeforeWindow_defersAndKeepsPending() {
        var mountedIDs: [UUID] = []
        let presenter = makePresenter(rootReady: { false }, mounted: { id in
            mountedIDs.append(id); return true
        })
        let id = UUID()

        presenter.requestPresentation(alarmID: id)

        XCTAssertTrue(mountedIDs.isEmpty, "Must not mount before the root is ready")
        XCTAssertEqual(presenter.pendingAlarmID, id,
                       "The alarm must stay pending until the scene is active")
    }

    /// A flush once the root is ready mounts the deferred alarm and clears the
    /// pending id — the cold-launch / scene-active recovery path.
    func testPresenter_flushAfterWindowReady_mountsAndClearsPending() {
        var rootReady = false
        var mountedIDs: [UUID] = []
        let presenter = makePresenter(rootReady: { rootReady }, mounted: { id in
            mountedIDs.append(id); return true
        })
        let id = UUID()

        presenter.requestPresentation(alarmID: id) // deferred (no root)
        rootReady = true
        presenter.flushPendingPresentation()        // scene became active

        XCTAssertEqual(mountedIDs, [id], "Flush must mount the deferred alarm once")
        XCTAssertNil(presenter.pendingAlarmID, "Pending must clear after a successful mount")
    }

    /// A flush that still finds no window keeps the alarm pending so a later
    /// activation re-attempts — it must not silently drop the firing screen.
    func testPresenter_flushWhileStillNotReady_keepsPending() {
        var mountedIDs: [UUID] = []
        let presenter = makePresenter(rootReady: { false }, mounted: { id in
            mountedIDs.append(id); return true
        })
        let id = UUID()

        presenter.requestPresentation(alarmID: id)
        presenter.flushPendingPresentation() // still no root

        XCTAssertTrue(mountedIDs.isEmpty)
        XCTAssertEqual(presenter.pendingAlarmID, id)
    }

    /// A mount that reports "no window" (returns false) even though the root
    /// gate passed keeps the alarm pending for the next flush — the window-race
    /// belt-and-suspenders.
    func testPresenter_mountReportsNoWindow_keepsPending() {
        var attempts = 0
        let presenter = makePresenter(rootReady: { true }, mounted: { _ in
            attempts += 1; return false
        })
        let id = UUID()

        presenter.requestPresentation(alarmID: id)

        XCTAssertEqual(attempts, 1, "Should attempt the mount when the root is ready")
        XCTAssertEqual(presenter.pendingAlarmID, id,
                       "A failed mount must keep the alarm pending")
    }

    /// A warm request (window already ready) mounts immediately and never
    /// records a pending id.
    func testPresenter_requestWithWindowReady_mountsImmediately() {
        var mountedIDs: [UUID] = []
        let presenter = makePresenter(rootReady: { true }, mounted: { id in
            mountedIDs.append(id); return true
        })
        let id = UUID()

        presenter.requestPresentation(alarmID: id)

        XCTAssertEqual(mountedIDs, [id])
        XCTAssertNil(presenter.pendingAlarmID)
    }
}
