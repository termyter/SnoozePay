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

    /// Every presenter line a test here recorded is checked for a whole id:
    /// `emit` writes `.public`, so the handle is all a line may carry (#835).
    override func tearDown() {
        for line in lines where line.message.hasPrefix("firing-present") {
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
        // Never completes; a test that needs the swap's second half holds it
        // with `holdingDismissals`.
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
        let swap = try XCTUnwrap(lines.first { $0.message.contains("swapping out") }, "\(lines.map(\.message))")
        XCTAssertEqual(swap.level, .error, "the older alarm's screen is lost to the queue: «\(swap.message)»")
        XCTAssertTrue(swap.message.contains("raised from the queue in this flush"), "«\(swap.message)»")
    }

    /// Stop drops the stopped alarm's record even when it is not the head,
    /// and leaves the other alarm's record in front of it.
    func testStop_forARecordBehindAnotherAlarm_dropsOnlyThatRecord() throws {
        let alarm = Alarm()
        let other = Alarm()
        let presenter = makePresenter(alarms: [alarm, other])
        let host = Host()
        top = host
        XCTAssertTrue(presenter.present(alarm: alarm), "test precondition: the screen went up")
        let screen = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        rootReady = false
        presenter.requestPresentation(alarmID: other.id)
        presenter.requestPresentation(alarmID: alarm.id)
        XCTAssertEqual(presenter.pendingPresentations, [pending(other, 0), pending(alarm, 0)], "test precondition")

        recording { screen.dismissTapped() }

        XCTAssertEqual(presenter.pendingPresentations, [pending(other, 0)])
        let stops = lines.filter { $0.message.contains("stopped on its screen") }
        XCTAssertEqual(stops.count, 1, "\(lines.map(\.message))")
        XCTAssertTrue(stops.first?.message.contains("alarm \(handle(alarm)) at snooze 0") ?? false)
    }

    // MARK: - Soon-retry (#875)

    /// Starts `alarm`'s sound, so its screen reads as the ringing one.
    private func ring(_ alarm: Alarm) {
        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarm.id)
    }

    /// Holds each swap's completion instead of dropping it, so a test can
    /// finish the dismissal and see what the swap raises.
    private func holdingDismissals(_ presenter: AlarmFiringPresenter) -> () -> [() -> Void] {
        var held: [() -> Void] = []
        presenter.dismissStaleScreen = { [self] screen, completion in
            self.dismissed.append(screen)
            held.append(completion)
        }
        return { held }
    }

    /// #875 item 1. B's record is the head and `(A, 3)` waits behind it when
    /// A goes up at 1, directly or by settling on its ringing screen. The
    /// retry looked at the head only, so nothing ran until the next
    /// activation and A stayed on the first step's price. Now the next turn
    /// runs the flush, oldest first: B's swap, then `(A, 3)` over B once B is
    /// up. It ends on A at 3, the newest ring, with no activation at all.
    func testShowingAnAlarm_withItsHigherRecordBehindAnotherAlarm_raisesItWithoutAnActivation() throws {
        for path in ["direct", "settle"] {
            dismissed = []
            lines = []
            defer { AudioService.shared.stopAlarmSound() }
            let alarm = Alarm()
            let other = Alarm()
            let presenter = makePresenter(alarms: [alarm, other])
            let completions = holdingDismissals(presenter)
            rootReady = false
            presenter.requestPresentation(alarmID: other.id)
            presenter.requestPresentation(alarmID: alarm.id, snoozeCount: 3)
            let queued = [pending(other, 0), pending(alarm, 3)]
            XCTAssertEqual(presenter.pendingPresentations, queued, "\(path): precondition")

            rootReady = true
            let host = Host()
            let atOne: UIViewController
            if path == "direct" {
                top = host
                XCTAssertTrue(presenter.present(alarm: alarm, snoozeCount: 1), "\(path): A never went up")
                atOne = try XCTUnwrap(host.presentedScreens.first, path)
            } else {
                atOne = makeScreen(alarm, snoozeCount: 1)
                ring(alarm)
                recording { XCTAssertTrue(presenter.present(alarm: alarm, snoozeCount: 1), path) }
                XCTAssertTrue(lines.contains { $0.message.contains("up and ringing") }, "\(lines.map(\.message))")
            }
            XCTAssertEqual(presenter.pendingPresentations, queued, path)
            XCTAssertTrue(dismissed.isEmpty, "\(path): swapped before the turn")

            top = atOne
            runOneMainQueueTurn()
            XCTAssertEqual(dismissed.count, 1, "\(path): the queue waited for an activation")
            XCTAssertTrue(dismissed.first === atOne, path)

            top = host
            try XCTUnwrap(completions().first, path)()
            let otherScreen = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen, path)
            XCTAssertEqual(otherScreen.viewModel.alarm.id, other.id, "\(path): the older record goes up first")
            XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 3)], path)

            top = otherScreen
            runOneMainQueueTurn()
            XCTAssertEqual(dismissed.count, 2, "\(path): (A, 3) was never attempted after B went up")
            top = host
            try XCTUnwrap(completions().last, path)()
            let landed = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen, path)
            XCTAssertEqual(landed.viewModel.alarm.id, alarm.id, path)
            XCTAssertEqual(landed.viewModel.snoozeCount, 3, "\(path): A is left on the lower count's price")
            XCTAssertTrue(presenter.pendingPresentations.isEmpty, path)
        }
    }

    /// #875 item 7. `(A, 3)` is parked when A's ringing screen at 1 is asked
    /// for again at 1. The settle keeps that screen and clears only the
    /// records it covers: `(A, 3)` stays, and is swapped in after one turn.
    func testSettle_overARingingLowerCountWithAHigherRecordParked_keepsTheRecordAndSwapsItIn() throws {
        let alarm = Alarm()
        let presenter = makePresenter(alarms: [alarm])
        let completions = holdingDismissals(presenter)
        rootReady = false
        presenter.requestPresentation(alarmID: alarm.id, snoozeCount: 3)
        rootReady = true
        let ringing = makeScreen(alarm, snoozeCount: 1)
        top = ringing
        ring(alarm)
        defer { AudioService.shared.stopAlarmSound() }

        var answer = false
        recording { answer = presenter.present(alarm: alarm, snoozeCount: 1) }
        XCTAssertTrue(answer, "the ringing screen is this request's")
        XCTAssertTrue(dismissed.isEmpty, "the settle swapped the ringing screen at once")
        XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 3)], "the settle cleared the later ring")
        XCTAssertTrue(
            lines.contains { $0.message.hasSuffix("not swapping it [alarm \(handle(alarm)) at snooze 1]") },
            "\(lines.map(\.message))"
        )

        lines = []
        recording { runOneMainQueueTurn() }
        XCTAssertEqual(dismissed.count, 1, "(A, 3) waited for an activation")
        XCTAssertTrue(dismissed.first === ringing)
        let swap = try XCTUnwrap(lines.first { $0.message.contains("swapping out") }, "\(lines.map(\.message))")
        XCTAssertTrue(swap.message.contains("(a lower snooze count)"), "«\(swap.message)»")
        XCTAssertTrue(swap.message.hasSuffix("[alarm \(handle(alarm)) at snooze 3]"), "«\(swap.message)»")

        let host = Host()
        top = host
        try XCTUnwrap(completions().first)()
        let swappedIn = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen, "(A, 3) never went up")
        XCTAssertEqual(swappedIn.viewModel.snoozeCount, 3)
        XCTAssertTrue(presenter.pendingPresentations.isEmpty)
    }

    // MARK: - Expiry

    /// A record parked past `pendingRecordLifetime` is dropped on the flush,
    /// at `.error`, naming it, even when it is not the head: the fresh record
    /// is first, since its count went up in place after the stale one parked.
    /// A retry at the same count does not restart the clock.
    func testFlush_dropsARecordPastItsLifetimeAndRaisesTheRest() throws {
        let stale = Alarm()
        let fresh = Alarm()
        let presenter = makePresenter(alarms: [stale, fresh])
        let parkedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = parkedAt
        presenter.now = { clock }
        let lifetime = AlarmFiringPresenter.pendingRecordLifetime
        rootReady = false
        recording {
            presenter.requestPresentation(alarmID: fresh.id)
            clock = parkedAt.addingTimeInterval(60)
            presenter.requestPresentation(alarmID: stale.id)
            clock = parkedAt.addingTimeInterval(60 * 60)
            presenter.requestPresentation(alarmID: stale.id)
            clock = parkedAt.addingTimeInterval(2 * 60 * 60)
            presenter.requestPresentation(alarmID: fresh.id, snoozeCount: 1)
        }
        XCTAssertEqual(presenter.pendingPresentations, [pending(fresh, 1), pending(stale, 0)], "test precondition")

        clock = parkedAt.addingTimeInterval(60 + lifetime)
        recording { presenter.flushPendingPresentation() }
        XCTAssertEqual(presenter.pendingPresentations.count, 2, "dropped at the limit, not past it")

        clock = parkedAt.addingTimeInterval(60 + lifetime + 60)
        let host = Host()
        top = host
        rootReady = true
        recording { presenter.flushPendingPresentation() }

        XCTAssertTrue(presenter.pendingPresentations.isEmpty, "only the head was checked for expiry")
        let drops = lines.filter { $0.message.contains("past the") }
        XCTAssertEqual(drops.count, 1, "\(lines.map(\.message))")
        XCTAssertEqual(drops.first?.level, .error)
        let limit = Int(lifetime / 60)
        XCTAssertEqual(
            drops.first?.message,
            "firing-present: dropped after \(limit + 1) min pending, past the \(limit) min limit"
                + " [alarm \(handle(stale)) at snooze 0] — leaving the audio of nobody alone",
            "the retry at 1 h restarted the clock, or the line changed"
        )
        let raised = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen, "the fresh record was lost")
        XCTAssertEqual(raised.viewModel.alarm.id, fresh.id)
        XCTAssertEqual(raised.viewModel.snoozeCount, 1)
        XCTAssertEqual(host.presentedScreens.count, 1, "the expired record went up")
    }

    /// An expired record's alarm with no screen up has no screen coming: the
    /// sound it owns stops with it. Another alarm's sound is left alone, and
    /// so is the expired alarm's own sound while its screen is up: that is
    /// the screen's ring, and nothing would restart it.
    func testExpiry_stopsOnlyTheOrphanSoundTheExpiredAlarmOwns() {
        for state in ["orphan", "other alarm's", "screen up"] {
            lines = []
            let expired = Alarm()
            let other = Alarm()
            let presenter = makePresenter(alarms: [expired])
            let parkedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var clock = parkedAt
            presenter.now = { clock }
            rootReady = false
            top = state == "screen up" ? makeScreen(expired) : nil
            presenter.requestPresentation(alarmID: expired.id)
            let owner = state == "other alarm's" ? other : expired
            AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: owner.id)

            clock = parkedAt.addingTimeInterval(AlarmFiringPresenter.pendingRecordLifetime + 60)
            recording { presenter.flushPendingPresentation() }

            XCTAssertTrue(presenter.pendingPresentations.isEmpty, state)
            XCTAssertEqual(AudioService.shared.soundingAlarmID, state == "orphan" ? nil : owner.id, state)
            let decision = [
                "orphan": "stopping the audio it owns", "other alarm's": "leaving the audio of \(handle(other)) alone",
                "screen up": "its screen is up, leaving it the audio"
            ][state] ?? ""
            XCTAssertTrue(
                lines.contains { $0.message.contains("[alarm \(handle(expired))") && $0.message.hasSuffix(decision) },
                "\(state): \(lines.map(\.message))"
            )
            AudioService.shared.stopAlarmSound()
        }
    }

    /// Review round 2: yesterday's `(A, 3)` expired in the queue, and today A
    /// rings and goes up directly at 0. The record outlived the screen, since
    /// its count was higher, and its drop on the next flush stopped the new
    /// screen's sound, as the sound's owner. Now the screen clears it.
    func testDirectPresent_overItsOwnExpiredHigherRecord_keepsTheSound() throws {
        let alarm = Alarm()
        let presenter = makePresenter(alarms: [alarm])
        let parkedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = parkedAt
        presenter.now = { clock }
        rootReady = false
        presenter.requestPresentation(alarmID: alarm.id, snoozeCount: 3)
        clock = parkedAt.addingTimeInterval(AlarmFiringPresenter.pendingRecordLifetime + 60)

        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarm.id)
        let host = Host()
        top = host
        rootReady = true
        var wentUp = false
        recording { wentUp = presenter.present(alarm: alarm, snoozeCount: 0) }
        XCTAssertTrue(wentUp, "test precondition: the screen went up")
        XCTAssertTrue(presenter.pendingPresentations.isEmpty, "the expired (A, 3) outlived A's screen")

        top = host.presentedScreens.first
        recording {
            presenter.flushPendingPresentation()
            runOneMainQueueTurn()
        }
        XCTAssertEqual(AudioService.shared.soundingAlarmID, alarm.id, "A's fresh screen went silent")
    }

    /// A request for an alarm whose record expired replaces that record
    /// rather than merging into it: at the same count it kept the old clock,
    /// and under yesterday's higher count it was outranked, and either way the
    /// flush dropped it with the old record.
    func testRequest_overItsOwnExpiredRecord_replacesItAndIsPresented() throws {
        for oldCount in [0, 3] {
            lines = []
            let alarm = Alarm()
            let presenter = makePresenter(alarms: [alarm])
            let parkedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var clock = parkedAt
            presenter.now = { clock }
            rootReady = false
            presenter.requestPresentation(alarmID: alarm.id, snoozeCount: oldCount)

            clock = parkedAt.addingTimeInterval(AlarmFiringPresenter.pendingRecordLifetime + 60)
            let host = Host()
            top = host
            rootReady = true
            recording { presenter.requestPresentation(alarmID: alarm.id) }

            let label = "expired at snooze \(oldCount)"
            let raised = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen, "\(label): no screen")
            XCTAssertEqual(raised.viewModel.snoozeCount, 0, label)
            XCTAssertTrue(presenter.pendingPresentations.isEmpty, label)
            XCTAssertFalse(lines.contains { $0.message.contains("past the") }, "\(label): \(lines.map(\.message))")
            let replaced = "replaces the expired alarm \(handle(alarm)) at snooze \(oldCount)"
            XCTAssertTrue(lines.contains { $0.message.contains(replaced) }, "\(label): \(lines.map(\.message))")
        }
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
