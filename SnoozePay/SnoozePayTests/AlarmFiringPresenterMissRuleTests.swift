import os
import XCTest
@testable import SnoozePay

/// #875 items 2 and 9: what a presenter miss that keeps the record does.
///
/// Item 2: the host miss in `present` stopped the audio, and the same miss
/// after a swap did not. Both now leave it alone: the record stays pending, so
/// its screen is still coming. Only a miss that ends the record stops the sound
/// that alarm owns (`AlarmFiringPresenterMissTests`, and the expiry in
/// `AlarmFiringPresenterQueueTests`).
///
/// Item 9: a swap in the queue's chain whose dismissal leaves no host. The swap
/// already took the old screen down, so nothing is up until the next
/// activation, which a foreground app does not get. The presenter retries on
/// the next turn, a bounded number of times. So does a host miss in `present`,
/// under the same budget: in the foreground the notification path shows no
/// banner for a ringing alarm, so nothing else raises it.
///
/// Every presenter reads a repository on this suite's own defaults, no screen
/// loads its view, and `tearDown` stops the audio and drains the main queue
/// (#846/#618).
@MainActor
final class AlarmFiringPresenterMissRuleTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    private final class Host: UIViewController {
        private(set) var presentedScreens: [UIViewController] = []

        override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
            presentedScreens.append(screen)
            (screen as? ReadBackFiringScreen)?.wiredPresenter = self
        }
    }

    private static let suite = "AlarmFiringPresenterMissRuleTests"
    private static let noHost = ActiveWindowLocator.Miss.noHostingWindow.rawValue
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

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
        defaults.removePersistentDomain(forName: Self.suite)
        top = nil
        dismissed = []
        lines = []
        super.tearDown()
    }

    /// A presenter over `alarms` whose swaps hold their completions: the test
    /// runs each one, as "the dismissal finished", after it has moved the host.
    private func makePresenter(alarms: [Alarm]) -> (AlarmFiringPresenter, completions: () -> [() -> Void]) {
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
        var held: [() -> Void] = []
        presenter.dismissStaleScreen = { [self] screen, completion in
            self.dismissed.append(screen)
            held.append(completion)
        }
        return (presenter, { held })
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

    // MARK: - Item 2: one rule for a miss that keeps the record

    /// A rings from the notification path and its screen finds no host, before
    /// any swap (`present`) or once a swap's dismissal finished
    /// (`mountAfterDismissal`). Either way A stays pending, and its sound is
    /// left on: `present` used to stop it, the swap never did.
    func testHostMiss_beforeAndAfterASwap_leavesThePendingAlarmsSoundOn() throws {
        for path in ["direct", "swap"] {
            lines = []
            let alarm = Alarm()
            let (presenter, completions) = makePresenter(alarms: [alarm])
            top = path == "swap" ? makeScreen(Alarm()) : nil
            AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarm.id)
            defer {
                AudioService.shared.stopAlarmSound()
                drainMainQueue()
            }

            recording { XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: 2), path) }
            if path == "swap" {
                top = nil
                let finish = try XCTUnwrap(completions().first, "\(path): the swap never started")
                recording { finish() }
            }

            XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 2)], path)
            XCTAssertEqual(
                AudioService.shared.soundingAlarmID, alarm.id,
                "\(path): the miss silenced the alarm whose screen is still coming"
            )
            let miss = try XCTUnwrap(
                lines.first { $0.message.contains("keeping it pending") }, "\(path): \(lines.map(\.message))"
            )
            XCTAssertEqual(miss.level, .error, "\(path): an alarm with no screen is a failure")
            XCTAssertTrue(
                miss.message.contains("keeping it pending; the in-app sound of \(handle(alarm)) is on"),
                "«\(miss.message)»"
            )
        }
    }

    // MARK: - Item 9: a chain broken by a host gone after the dismissal

    /// Queue `[B, (A, 3)]` and A goes up at 1. The next turn swaps A1 out for
    /// B, and the one after swaps B out for A3. That dismissal finishes with
    /// no host: B is down, nothing replaced it, A waits at 3, and nobody owns
    /// the sound (each screen's `viewDidDisappear` took its own down). One
    /// `.error` line says so. The next turn raises A at 3, with no activation.
    func testMidChain_whenTheHostIsGoneAfterTheSecondSwap_leavesNoScreenThenRaisesTheRecordNextTurn() throws {
        let alarm = Alarm()
        let other = Alarm()
        let (presenter, completions) = makePresenter(alarms: [alarm, other])
        rootReady = false
        presenter.requestPresentation(alarmID: other.id)
        presenter.requestPresentation(alarmID: alarm.id, snoozeCount: 3)
        rootReady = true
        let host = Host()
        top = host
        XCTAssertTrue(presenter.present(alarm: alarm, snoozeCount: 1), "test precondition: A went up at 1")
        top = try XCTUnwrap(host.presentedScreens.first)
        runOneMainQueueTurn()
        top = host
        try XCTUnwrap(completions().first, "test precondition: the retry swaps A at 1 out")()
        let otherScreen = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen)
        XCTAssertEqual(otherScreen.viewModel.alarm.id, other.id, "test precondition: B goes up first")
        top = otherScreen
        runOneMainQueueTurn()
        XCTAssertEqual(dismissed.count, 2, "test precondition: (A, 3) starts its swap over B")

        top = nil
        let finish = try XCTUnwrap(completions().last)
        recording { finish() }

        XCTAssertEqual(host.presentedScreens.count, 2, "a screen went up with no host")
        XCTAssertTrue(dismissed.last === otherScreen, "B stayed up")
        XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 3)], "A's record went with its screen")
        XCTAssertNil(AudioService.shared.currentAlarmID, "the miss started or kept a sound")
        XCTAssertEqual(lines.map(\.level), [.error], "\(lines.map(\.message))")
        XCTAssertEqual(lines.map(\.message), [
            "firing-present: \(Self.noHost) after dismissing the previous screen — keeping it pending;"
                + " no in-app sound is on; retrying on the next turn [alarm \(handle(alarm)) at snooze 3]"
        ])

        top = host
        runOneMainQueueTurn()
        XCTAssertEqual(host.presentedScreens.count, 3, "A waits for an activation the foreground app does not get")
        let landed = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen)
        XCTAssertEqual(landed.viewModel.alarm.id, alarm.id)
        XCTAssertEqual(landed.viewModel.snoozeCount, 3, "A is back at the wrong price")
        XCTAssertTrue(presenter.pendingPresentations.isEmpty, "\(presenter.pendingPresentations)")
    }

    /// The retry cannot spin: a firing screen found on every turn and no host
    /// after every dismissal is retried `hostGoneRetryLimit` times, then the
    /// line says the record waits for the activation. A screen going up
    /// refills the budget, as it does the stale-survival one.
    func testHostGoneAfterEverySwap_retriesABoundedNumberOfTimesUntilAScreenGoesUp() throws {
        let alarm = Alarm()
        let (presenter, completions) = makePresenter(alarms: [alarm])
        let stale = makeScreen(Alarm())
        top = stale
        XCTAssertFalse(presenter.present(alarm: alarm), "test precondition: the swap started")

        let limit = AlarmFiringPresenter.hostGoneRetryLimit
        for round in 0...limit {
            let held = completions()
            guard held.count == round + 1 else {
                return XCTFail("round \(round): \(held.count) swaps; \(lines.map(\.message))")
            }
            top = nil
            recording { held[round]() }
            top = stale
            runOneMainQueueTurn()
        }

        XCTAssertEqual(dismissed.count, limit + 1, "the retry spun past its limit")
        let decisions = lines.filter { $0.message.contains("after dismissing the previous screen") }.map {
            $0.message.contains("; retrying on the next turn [") ? "retry"
                : $0.message.contains("; waiting for the next activation [") ? "wait" : $0.message
        }
        XCTAssertEqual(decisions, Array(repeating: "retry", count: limit) + ["wait"])
        XCTAssertEqual(lines.last?.level, .error)
        XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 0)], "the record has to wait, not go")

        let host = Host()
        top = host
        presenter.flushPendingPresentation()
        XCTAssertEqual(host.presentedScreens.count, 1, "test precondition: the activation raised A")
        top = stale
        XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: 1), "test precondition: another swap")
        top = nil
        lines = []
        let finish = try XCTUnwrap(completions().last)
        recording { finish() }
        XCTAssertTrue(
            lines.contains { $0.message.contains("; retrying on the next turn [") },
            "a screen going up did not refill the budget: \(lines.map(\.message))"
        )
    }

    // MARK: - The host miss in `present` re-arms too

    /// Misses the host in `present` and runs one turn more than the budget
    /// needs, so a retry past it would show.
    private func spendHostMissBudget(_ presenter: AlarmFiringPresenter, on alarm: Alarm, count: Int) {
        top = nil
        recording {
            XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: count), "test precondition: a host miss")
            for _ in 0...AlarmFiringPresenter.hostGoneRetryLimit { runOneMainQueueTurn() }
        }
    }

    /// The legacy notification path in the foreground: `willPresent` shows no
    /// banner for a ringing alarm, so a host miss in `present` had no screen
    /// and no retry until the next activation. It re-arms under the swap's
    /// budget: `retry, retry, wait`, and the record keeps its count.
    func testHostMissInPresent_retriesUpToTheLimitThenWaitsForTheActivation() throws {
        let alarm = Alarm()
        let (presenter, _) = makePresenter(alarms: [alarm])
        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarm.id)
        defer {
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }

        spendHostMissBudget(presenter, on: alarm, count: 1)

        let misses = lines.filter { $0.message.contains("keeping it pending") }
        let decisions = misses.map {
            $0.message.contains("; retrying on the next turn [") ? "retry"
                : $0.message.contains("; waiting for the next activation [") ? "wait" : $0.message
        }
        XCTAssertEqual(decisions, Array(repeating: "retry", count: AlarmFiringPresenter.hostGoneRetryLimit) + ["wait"])
        XCTAssertEqual(
            misses.first?.message,
            "firing-present: \(Self.noHost) — keeping it pending; the in-app sound of \(handle(alarm)) is on;"
                + " retrying on the next turn [alarm \(handle(alarm)) at snooze 1]"
        )
        XCTAssertTrue(misses.allSatisfy { $0.level == .error }, "an alarm with no screen is a failure")
        XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 1)], "the record has to wait, not go")
        XCTAssertEqual(AudioService.shared.soundingAlarmID, alarm.id, "a miss that keeps the record stopped its sound")

        let host = Host()
        top = host
        presenter.flushPendingPresentation()
        let landed = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen, "the flush raised nothing")
        XCTAssertEqual(landed.viewModel.snoozeCount, 1, "the retry restarted the snooze ladder (#808)")
    }

    /// The swap's completion finding this alarm's screen already up and
    /// ringing refills the budget, as a screen going up does. Without the
    /// reset there, the next host miss waits for the activation at once.
    func testThisAlarmsScreenAlreadyUpAfterASwap_refillsTheHostMissBudget() throws {
        let alarm = Alarm()
        let (presenter, completions) = makePresenter(alarms: [alarm])
        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarm.id)
        defer {
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }
        spendHostMissBudget(presenter, on: alarm, count: 0)
        XCTAssertTrue(lines.last?.message.contains("; waiting for the next activation [") ?? false, "precondition")

        top = makeScreen(Alarm())
        XCTAssertFalse(presenter.present(alarm: alarm), "test precondition: the swap started")
        top = makeScreen(alarm)
        lines = []
        let finish = try XCTUnwrap(completions().last, "test precondition: no swap is outstanding")
        recording { finish() }
        XCTAssertTrue(
            lines.contains { $0.message.contains("already up — not stacking") }, "precondition: \(lines.map(\.message))"
        )

        top = nil
        lines = []
        recording { _ = presenter.present(alarm: alarm, snoozeCount: 1) }
        XCTAssertTrue(
            lines.contains { $0.message.contains("; retrying on the next turn [") },
            "the already-up branch did not refill the budget: \(lines.map(\.message))"
        )
    }
}
