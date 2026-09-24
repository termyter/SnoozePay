import os
import XCTest
@testable import SnoozePay

/// #875 items 3, 5 and 6: the presenter meeting a UIKit transition, and the
/// dismissal it sends for a swap.
///
/// Item 3: a `present` refused by a host that is being presented or dismissed
/// waited for the next activation, which a foreground app does not get. It is
/// asked again when that transition ends, one main-queue turn after it and
/// `transitionRetryLimit` times at most, parked before the retry is scheduled.
/// A refusal with no transition still waits
/// (`AlarmFiringPresenterSwapGuardTests`, the direct-refusal test).
///
/// Item 6 (FU-3): a swap over a firing screen still in a transition sent its
/// `dismiss` mid-transition, which UIKit drops with its completion. It now
/// waits for the end of that transition and asks again.
///
/// Item 5 (FU-2): the production dismissal went to the stale screen's presenter
/// even when that presenter no longer presented it, and `dismiss` on a
/// controller with nothing presented takes that controller down itself.
///
/// The transition is the ``AlarmFiringPresenter/whenTransitionEnds`` seam: the
/// test holds the closure and runs it as "the transition ended". Every screen
/// reads this suite's own defaults, none loads its view, and `tearDown` stops
/// the audio and drains the main queue (#846/#618).
@MainActor
final class AlarmFiringPresenterTransitionTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    /// A non-firing host that answers `presentedViewController` as UIKit does.
    /// `accepts == false` is UIKit declining: the ask is recorded, nothing is wired.
    private final class Host: UIViewController {
        var accepts = true
        weak var presented: UIViewController?
        private(set) var presentedScreens: [UIViewController] = []
        private(set) var dismissCalls = 0

        override var presentedViewController: UIViewController? { presented }

        override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
            presentedScreens.append(screen)
            guard accepts else { return }
            (screen as? ReadBackFiringScreen)?.wiredPresenter = self
            presented = screen
        }

        override func dismiss(animated flag: Bool, completion: (() -> Void)?) {
            dismissCalls += 1
        }
    }

    /// Something the stale firing screen presented itself: the WokeMorning summary.
    private final class Sheet: UIViewController {
        weak var presentedBy: UIViewController?
        override var presentingViewController: UIViewController? { presentedBy }
    }

    private static let suite = "AlarmFiringPresenterTransitionTests"
    private let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
    /// What `locateHost` answers, first to last; the last one repeats.
    private var hosts: [UIViewController] = []
    /// Controllers in a transition, by the seam.
    private var inTransition: [UIViewController] = []
    /// Closures waiting for a transition to end.
    private var held: [() -> Void] = []
    /// Retries scheduled through the `whenTransitionEnds` seam.
    private var scheduled = 0
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
        hosts = []
        inTransition = []
        held = []
        scheduled = 0
        dismissed = []
        lines = []
        super.tearDown()
    }

    /// `holdsDismissals == false` leaves `dismissStaleScreen` at its default.
    private func makePresenter(alarms: [Alarm], holdsDismissals: Bool = true) -> AlarmFiringPresenter {
        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        let presenter = AlarmFiringPresenter(alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler))
        presenter.locateHost = { [self] in
            guard let first = self.hosts.first else { return .failure(.noHostingWindow) }
            if self.hosts.count > 1 { self.hosts.removeFirst() }
            return .success(first)
        }
        presenter.isRootReady = { true }
        presenter.reportDataCorrupted = { XCTFail("unexpected corruption report: \($0)") }
        presenter.makeFiringScreen = { [self] in self.makeScreen($0, snoozeCount: $1) }
        presenter.mount = { [weak presenter] alarmID, count in
            guard let presenter, let alarm = byID[alarmID] else { return false }
            return presenter.present(alarm: alarm, snoozeCount: count)
        }
        presenter.isInTransition = { [self] controller in self.inTransition.contains { $0 === controller } }
        presenter.whenTransitionEnds = { [self] controller, body in
            guard self.inTransition.contains(where: { $0 === controller }) else { return false }
            self.scheduled += 1
            self.held.append(body)
            return true
        }
        if holdsDismissals {
            presenter.dismissStaleScreen = { [self] screen, _ in self.dismissed.append(screen) }
        }
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

    /// Runs what waits for the transition, then the main-queue turn its
    /// retry hops to. `clears == false` is UIKit still reporting a
    /// transition when the retry arrives: a new one, or the same one.
    private func endTransition(clears: Bool = true) throws {
        if clears { inTransition = [] }
        let bodies = held
        held = []
        XCTAssertFalse(bodies.isEmpty, "test precondition: something has to wait for the transition")
        recording {
            bodies.forEach { $0() }
            drainMainQueue()
        }
    }

    private func pending(_ alarm: Alarm, _ count: Int) -> AlarmFiringPresenter.PendingPresentation {
        AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: count)
    }

    // MARK: - Item 3: a refusal by a host in a transition

    /// The notification path's direct present meets a sheet that is still
    /// coming in or going out. Nothing raised the alarm again until the next
    /// activation; now the end of that transition does, and not a turn before.
    func testDirect_refusedByAHostInATransition_isAskedAgainWhenItEnds() throws {
        let alarm = Alarm()
        let host = Host()
        host.accepts = false
        hosts = [host]
        inTransition = [host]
        let presenter = makePresenter(alarms: [alarm])

        recording { XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: 1)) }

        XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 1)])
        let line = try XCTUnwrap(lines.first { $0.message.contains("keeping it pending") }, "\(lines.map(\.message))")
        XCTAssertTrue(line.message.contains("retrying once its transition ends"), "«\(line.message)»")
        XCTAssertEqual(line.level, .error)
        for _ in 0..<3 { drainMainQueue() }
        XCTAssertEqual(host.presentedScreens.count, 1, "re-asked inside the transition, where UIKit refuses again")

        host.accepts = true
        try endTransition()

        XCTAssertEqual(host.presentedScreens.count, 2, "the end of the transition has to ask again")
        let screen = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen)
        XCTAssertTrue(screen.presentingViewController === host)
        XCTAssertEqual(screen.viewModel.snoozeCount, 1, "the retry keeps the count (#808)")
        XCTAssertTrue(presenter.pendingPresentations.isEmpty)
    }

    // MARK: - Item 3: the bound, and a completion UIKit runs at once

    /// UIKit reports a transition on every retry: a new sheet each time, or
    /// one that never clears. Each end schedules at most one retry, a turn
    /// later, `transitionRetryLimit` in all. Then the record waits for the
    /// activation, and the line says so.
    func testDirect_whenTheTransitionNeverClears_retriesUpToTheLimitThenWaits() throws {
        let limit = AlarmFiringPresenter.transitionRetryLimit
        let alarm = Alarm()
        let host = Host()
        host.accepts = false
        hosts = [host]
        inTransition = [host]
        let presenter = makePresenter(alarms: [alarm])

        recording { XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: 1)) }
        for _ in 0..<limit { try endTransition(clears: false) }

        XCTAssertEqual(scheduled, limit, "one retry per refusal, up to the limit")
        XCTAssertEqual(host.presentedScreens.count, 1 + limit, "the first ask and one per retry")
        XCTAssertTrue(held.isEmpty, "past the limit nothing waits for the transition")
        let refusals = lines.filter { $0.message.contains("keeping it pending") }.map(\.message)
        XCTAssertEqual(refusals.count, 1 + limit, "\(lines.map(\.message))")
        let retried = refusals.dropLast().allSatisfy { $0.contains("retrying once its transition ends") }
        XCTAssertTrue(retried, "\(refusals)")
        let last = try XCTUnwrap(refusals.last)
        XCTAssertTrue(last.contains("waiting for the next activation"), "«\(last)»")
        XCTAssertFalse(last.contains("retrying"), "«\(last)»")
        XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 1)], "kept for the activation")

        for _ in 0..<3 { drainMainQueue() }
        XCTAssertEqual(host.presentedScreens.count, 1 + limit, "nothing else asks before the activation")
        XCTAssertEqual(scheduled, limit)
    }

    /// UIKit may run the completion inside `animate(alongsideTransition:)`.
    /// The record is parked by then and the retry comes a turn later, not
    /// inside the call. A host that still refuses there cannot recurse: the
    /// retries stay within the limit.
    func testDirect_whenTheCompletionRunsInsideTheCall_theRecordIsParkedAndTheRetryWaitsATurn() throws {
        for hostAcceptsTheRetry in [true, false] {
            let path = hostAcceptsTheRetry ? "accepted on retry" : "refused on every retry"
            let alarm = Alarm()
            let host = Host()
            host.accepts = false
            hosts = [host]
            inTransition = [host]
            scheduled = 0
            lines = []
            let presenter = makePresenter(alarms: [alarm])
            var parkedAtCompletion: [[AlarmFiringPresenter.PendingPresentation]] = []
            var presentsAtCompletion: [Int] = []
            presenter.whenTransitionEnds = { [self, weak presenter] controller, body in
                guard self.inTransition.contains(where: { $0 === controller }) else { return false }
                self.scheduled += 1
                parkedAtCompletion.append(presenter?.pendingPresentations ?? [])
                presentsAtCompletion.append(host.presentedScreens.count)
                body()
                XCTAssertEqual(host.presentedScreens.count, presentsAtCompletion.last, "\(path): asked inside the call")
                return true
            }
            defer {
                AudioService.shared.stopAlarmSound()
                drainMainQueue()
            }

            recording { XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: 1), path) }

            XCTAssertEqual(parkedAtCompletion, [[pending(alarm, 1)]], "\(path): parked before the retry was scheduled")
            XCTAssertEqual(host.presentedScreens.count, 1, "\(path): no retry inside the completion")
            let line = try XCTUnwrap(lines.first { $0.message.contains("keeping it pending") }, path)
            XCTAssertTrue(line.message.contains("retrying once its transition ends"), "\(path): «\(line.message)»")

            if hostAcceptsTheRetry {
                host.accepts = true
                inTransition = []
            }
            // One turn per retry: a drain leaves what its last turn enqueued.
            recording { for _ in 0...AlarmFiringPresenter.transitionRetryLimit { drainMainQueue() } }

            if hostAcceptsTheRetry {
                XCTAssertEqual(host.presentedScreens.count, 2, "\(path): the retry comes on the next turn")
                XCTAssertEqual(scheduled, 1, path)
                XCTAssertTrue(presenter.pendingPresentations.isEmpty, path)
            } else {
                let limit = AlarmFiringPresenter.transitionRetryLimit
                XCTAssertEqual(scheduled, limit, "\(path): bounded even when the completion runs at once")
                XCTAssertEqual(host.presentedScreens.count, 1 + limit, path)
                let last = try XCTUnwrap(lines.last { $0.message.contains("keeping it pending") }, path)
                XCTAssertTrue(last.message.contains("waiting for the next activation"), "\(path): «\(last.message)»")
                XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 1)], path)
            }
        }
    }

    // MARK: - Item 6: a swap over a screen in a transition

    /// Another alarm's screen is still animating (in, out, or a sheet on it).
    /// No `dismiss` goes out mid-transition. At its end the request is asked
    /// again: put up directly when the screen is gone, swapped in when it
    /// stayed.
    func testSwap_overAScreenInATransition_waitsForItsEndInsteadOfDismissing() throws {
        for staleStays in [false, true] {
            let path = staleStays ? "stale screen stayed" : "stale screen gone"
            let alarm = Alarm()
            let root = Host()
            let stale = makeScreen(Alarm())
            stale.wiredPresenter = root
            hosts = [stale]
            inTransition = [stale]
            dismissed = []
            lines = []
            let presenter = makePresenter(alarms: [alarm])
            defer {
                AudioService.shared.stopAlarmSound()
                drainMainQueue()
            }

            recording { XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: 2), path) }

            XCTAssertTrue(dismissed.isEmpty, "\(path): a dismissal mid-transition is dropped with its completion")
            XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 2)], path)
            let line = try XCTUnwrap(lines.first { $0.message.contains("is in a transition") }, path)
            XCTAssertEqual(line.level, .default, path)

            if !staleStays { hosts = [root] }
            try endTransition()

            if staleStays {
                XCTAssertEqual(dismissed.count, 1, "\(path): the swap has to go ahead once the transition ends")
                XCTAssertTrue(dismissed.first === stale, path)
                XCTAssertEqual(presenter.pendingPresentations, [pending(alarm, 2)], "\(path): parked for the swap")
            } else {
                XCTAssertTrue(dismissed.isEmpty, "\(path): nothing is left to dismiss")
                let screen = try XCTUnwrap(root.presentedScreens.first as? ReadBackFiringScreen, path)
                XCTAssertEqual(screen.viewModel.alarm.id, alarm.id, path)
                XCTAssertTrue(presenter.pendingPresentations.isEmpty, path)
            }
        }
    }

    // MARK: - Item 5: the production dismissal

    /// The dismissal goes to the stale screen's presenter, which takes the
    /// screen down together with anything it presented (#807). Moved here from
    /// the swap-guard suite, whose host did not answer `presentedViewController`.
    func testDefaultDismissal_goesToThePresenterThatStillPresentsTheStaleScreen() {
        let host = Host()
        let stale = makeScreen(Alarm())
        stale.wiredPresenter = host
        host.presented = stale
        let summary = Sheet()
        summary.presentedBy = stale
        hosts = [summary]
        let presenter = makePresenter(alarms: [], holdsDismissals: false)

        _ = presenter.present(alarm: Alarm())

        XCTAssertEqual(stale.dismissCalls, 0, "sent to the stale screen, which only takes down what it presented")
        XCTAssertEqual(host.dismissCalls, 1, "the stale screen's presenter has to receive the dismissal")
    }

    /// The presenter's `presentedViewController` is already nil. `dismiss` on
    /// it would take the presenter itself down (an alarm-edit sheet with its
    /// changes). No dismissal goes out, and the swap goes on to the host the
    /// walk finds next.
    func testDefaultDismissal_whenThePresenterNoLongerPresentsIt_sendsNoneAndSwapsOn() throws {
        let alarm = Alarm()
        let formerPresenter = Host()
        let stale = makeScreen(Alarm())
        stale.wiredPresenter = formerPresenter
        let nextHost = Host()
        hosts = [stale, nextHost]
        let presenter = makePresenter(alarms: [alarm], holdsDismissals: false)

        recording { XCTAssertFalse(presenter.present(alarm: alarm)) }

        XCTAssertEqual(formerPresenter.dismissCalls, 0, "dismiss on a presenter with nothing up takes itself down")
        XCTAssertEqual(stale.dismissCalls, 0)
        let line = try XCTUnwrap(
            lines.first { $0.message.contains("no longer presents the previous screen") }, "\(lines.map(\.message))"
        )
        XCTAssertEqual(line.level, .error, "a presenter that lost its screen is a broken invariant")
        let staleHandle = AlarmFiringPresenter.PendingPresentation(on: stale).logHandle
        XCTAssertTrue(line.message.contains("[\(staleHandle)]"), "names the stale screen: «\(line.message)»")
        XCTAssertTrue(line.message.contains("(it presents nothing)"), "says what it holds: «\(line.message)»")
        XCTAssertTrue(line.message.contains("\(type(of: formerPresenter))"), "«\(line.message)»")
        let screen = try XCTUnwrap(nextHost.presentedScreens.first as? ReadBackFiringScreen, "the swap stopped")
        XCTAssertEqual(screen.viewModel.alarm.id, alarm.id)
        XCTAssertTrue(presenter.pendingPresentations.isEmpty)
    }
}
