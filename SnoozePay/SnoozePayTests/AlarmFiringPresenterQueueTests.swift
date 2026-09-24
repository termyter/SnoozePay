import os
import XCTest
@testable import SnoozePay

/// #858: the pending queue that replaced the one slot. One record per alarm,
/// the higher count wins, the flush goes in arrival order, and a record past
/// `pendingRecordLifetime` is dropped with a line. Also the order of the
/// flush's checks, and the handle every presenter line names an alarm by.
///
/// Every presenter here reads a repository on this suite's own defaults, so a
/// flush for an alarm not in `alarms` is a real "not found" miss and nothing
/// touches `.standard`. No screen loads its view, and `tearDown` stops the
/// audio and drains the main queue (#846/#618).
@MainActor
final class AlarmFiringPresenterQueueTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    private final class Host: UIViewController {
        private(set) var presentedScreens: [UIViewController] = []

        override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
            presentedScreens.append(screen)
            (screen as? ReadBackFiringScreen)?.wiredPresenter = self
        }
    }

    private static let suite = "AlarmFiringPresenterQueueTests"
    private static let fullUUID = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
    private let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
    private var top: UIViewController?
    private var rootReady = true
    private var dismissed: [UIViewController] = []
    private var lines: [Line] = []

    override func setUp() {
        super.setUp()
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
    }

    /// Every line a test here recorded is checked for a whole id: `emit`
    /// writes `.public`, so the handle is all a line may carry (#835).
    override func tearDown() {
        for line in lines {
            let whole = line.message.range(of: Self.fullUUID, options: [.regularExpression, .caseInsensitive])
            XCTAssertNil(whole, "a presenter line carries a full UUID: «\(line.message)»")
        }
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
        defaults.removePersistentDomain(forName: Self.suite)
        top = nil
        dismissed = []
        lines = []
        super.tearDown()
    }

    private func makePresenter(alarms: [Alarm]) -> AlarmFiringPresenter {
        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        let presenter = AlarmFiringPresenter(alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler))
        presenter.locateHost = { [self] in
            guard let top = self.top else { return .failure(.noHostingWindow) }
            return .success(top)
        }
        presenter.isRootReady = { [self] in self.rootReady }
        presenter.reportDataCorrupted = { XCTFail("unexpected corruption report: \($0)") }
        presenter.makeFiringScreen = { [self] in self.makeScreen($0, snoozeCount: $1) }
        presenter.mount = { [weak presenter] alarmID, count in
            guard let presenter else { return false }
            guard let alarm = byID[alarmID] else { return presenter.present(alarmID: alarmID, snoozeCount: count) }
            return presenter.present(alarm: alarm, snoozeCount: count)
        }
        // Never completes: no test here needs the swap's second half.
        presenter.dismissStaleScreen = { [self] screen, _ in self.dismissed.append(screen) }
        return presenter
    }

    private func makeScreen(_ alarm: Alarm, snoozeCount: Int = 0) -> ReadBackFiringScreen {
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        return ReadBackFiringScreen(viewModel: AlarmFiringViewModel(
            alarm: alarm, snoozeCount: snoozeCount,
            balanceService: BalanceService(defaults: defaults),
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler),
            scheduler: scheduler,
            wakeStore: WakeEventStore(defaults: defaults),
            ledger: TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults))
        ))
    }

    private func recording(_ body: () -> Void) {
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: body)
    }

    private func runOneMainQueueTurn() {
        let turn = expectation(description: "one main-queue turn")
        DispatchQueue.main.async { turn.fulfill() }
        wait(for: [turn], timeout: 10)
    }

    private func handle(_ alarm: Alarm) -> String { String(alarm.id.uuidString.prefix(8)) }

    private func pending(_ alarm: Alarm, _ count: Int) -> AlarmFiringPresenter.PendingPresentation {
        AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: count)
    }

    // MARK: - Queue

    /// #869 item 2. A rings from the notification path and is parked over the
    /// splash; AlarmKit then asks for B, which was deleted. The slot let B's
    /// request drop A's record: the flush missed B, left A's sound alone, and
    /// A rang with no screen and no retry. The queue raises A, then misses B.
    func testFlush_whenANewerRequestIsForADeletedAlarm_stillRaisesTheSoundOwnersScreen() throws {
        let owner = Alarm()
        let deleted = Alarm()
        let presenter = makePresenter(alarms: [owner])
        rootReady = false
        let host = Host()
        top = host
        recording { _ = presenter.present(alarm: owner) }
        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: owner.id)
        recording { presenter.requestPresentation(alarmID: deleted.id) }
        XCTAssertEqual(presenter.pendingPresentations, [pending(owner, 0), pending(deleted, 0)], "test precondition")

        rootReady = true
        recording { presenter.flushPendingPresentation() }
        recording { runOneMainQueueTurn() }

        let raised = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen, "A's screen never went up")
        XCTAssertEqual(raised.viewModel.alarm.id, owner.id)
        XCTAssertEqual(host.presentedScreens.count, 1)
        XCTAssertEqual(AudioService.shared.soundingAlarmID, owner.id, "the miss for B silenced A")
        XCTAssertTrue(presenter.pendingPresentations.isEmpty, "\(presenter.pendingPresentations)")
        XCTAssertTrue(
            lines.contains { $0.message.contains("not found [alarm \(handle(deleted)) at snooze 0]") },
            "B was never flushed: \(lines.map(\.message))"
        )
    }

    /// One record per alarm: a higher count replaces it in place, a lower one
    /// leaves it. The flush goes oldest first, and B, which arrived after A,
    /// starts its swap over A's screen on the next turn.
    func testQueue_keepsOneRecordPerAlarmAtItsHighestCountAndFlushesInArrivalOrder() throws {
        let first = Alarm()
        let second = Alarm()
        let presenter = makePresenter(alarms: [first, second])
        rootReady = false
        recording {
            presenter.requestPresentation(alarmID: first.id, snoozeCount: 1)
            presenter.requestPresentation(alarmID: second.id)
            presenter.requestPresentation(alarmID: first.id, snoozeCount: 3)
            presenter.requestPresentation(alarmID: first.id, snoozeCount: 0)
        }
        XCTAssertEqual(presenter.pendingPresentations, [pending(first, 3), pending(second, 0)])

        let host = Host()
        top = host
        rootReady = true
        recording { presenter.flushPendingPresentation() }
        let firstScreen = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        XCTAssertEqual(firstScreen.viewModel.alarm.id, first.id, "the older alarm has to go up first")
        XCTAssertEqual(firstScreen.viewModel.snoozeCount, 3)
        XCTAssertEqual(presenter.pendingPresentations, [pending(second, 0)])

        top = firstScreen
        recording { runOneMainQueueTurn() }
        XCTAssertTrue(dismissed.last === firstScreen, "the newer alarm was never raised after the older one")
    }

    // MARK: - Expiry

    /// A record parked past `pendingRecordLifetime` is dropped on the flush,
    /// at `.error`, naming it. A retry of the same record does not restart
    /// its clock; a record inside the lifetime still goes up.
    func testFlush_dropsARecordPastItsLifetimeAndRaisesTheRest() throws {
        let stale = Alarm()
        let fresh = Alarm()
        let presenter = makePresenter(alarms: [stale, fresh])
        let parkedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = parkedAt
        presenter.now = { clock }
        let lifetime = AlarmFiringPresenter.pendingRecordLifetime
        rootReady = false
        recording { presenter.requestPresentation(alarmID: stale.id) }
        clock = parkedAt.addingTimeInterval(60 * 60)
        recording {
            presenter.requestPresentation(alarmID: stale.id)
            presenter.requestPresentation(alarmID: fresh.id)
        }

        clock = parkedAt.addingTimeInterval(lifetime)
        recording { presenter.flushPendingPresentation() }
        XCTAssertEqual(presenter.pendingPresentations, [pending(stale, 0), pending(fresh, 0)], "dropped at the limit")

        clock = parkedAt.addingTimeInterval(lifetime + 60)
        let host = Host()
        top = host
        rootReady = true
        recording { presenter.flushPendingPresentation() }

        let drops = lines.filter { $0.message.contains("dropping") }
        XCTAssertEqual(drops.count, 1, "\(lines.map(\.message))")
        XCTAssertEqual(drops.first?.level, .error)
        let limit = Int(lifetime / 60)
        XCTAssertEqual(
            drops.first?.message,
            "firing-present: pending for \(limit + 1) min, past the \(limit) min limit"
                + " — dropping [alarm \(handle(stale)) at snooze 0]",
            "the retry at 1 h restarted the clock, or the line changed"
        )
        let raised = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen, "the fresh record was lost")
        XCTAssertEqual(raised.viewModel.alarm.id, fresh.id)
        XCTAssertEqual(host.presentedScreens.count, 1, "the expired record went up")
        XCTAssertTrue(presenter.pendingPresentations.isEmpty)
    }

    // MARK: - Check order

    /// The flush asks the root gate first and looks for a host only once it is
    /// open; the swap comes after the host (#858). Behind a closed gate the
    /// splash is still up, and a screen swapped in over it is torn down.
    func testFlush_checksTheRootGateThenTheHostThenSwaps() {
        let alarm = Alarm()
        let presenter = makePresenter(alarms: [alarm])
        var calls: [String] = []
        presenter.isRootReady = { [self] in
            calls.append("isRootReady")
            return self.rootReady
        }
        presenter.locateHost = { [self] in
            calls.append("locateHost")
            guard let top = self.top else { return .failure(.noHostingWindow) }
            return .success(top)
        }
        presenter.dismissStaleScreen = { _, _ in calls.append("swap") }
        rootReady = false
        top = makeScreen(Alarm())

        recording { presenter.requestPresentation(alarmID: alarm.id) }
        XCTAssertEqual(calls, ["isRootReady"], "a closed gate went on to the host")

        calls = []
        rootReady = true
        recording { presenter.flushPendingPresentation() }
        XCTAssertEqual(calls, ["isRootReady", "locateHost", "swap"])
    }

    // MARK: - Handle

    /// The handle on a known id: eight hex digits and the count, the form the
    /// release logs are searched by (#835), in the line of a real park.
    func testLogHandle_onAFixedID_isEightDigitsAndTheCount() throws {
        let id = try XCTUnwrap(UUID(uuidString: "1A2B3C4D-5E6F-4A1B-8C2D-3E4F5A6B7C8D"))
        let request = AlarmFiringPresenter.PendingPresentation(alarmID: id, snoozeCount: 2)
        XCTAssertEqual(request.logHandle, "alarm 1A2B3C4D at snooze 2")

        let alarm = Alarm(id: id)
        let presenter = makePresenter(alarms: [alarm])
        rootReady = false
        top = Host()
        recording { _ = presenter.present(alarm: alarm, snoozeCount: 2) }
        XCTAssertEqual(
            lines.map(\.message),
            ["firing-present: launch root not ready — keeping it pending [alarm 1A2B3C4D at snooze 2]"]
        )
    }
}
