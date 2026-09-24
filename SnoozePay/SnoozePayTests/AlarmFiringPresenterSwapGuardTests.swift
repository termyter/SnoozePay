import os
import XCTest
@testable import SnoozePay

/// A firing screen that answers what the presenter asks UIKit about it: its
/// `presentingViewController` is whoever accepted it (the read-back), and
/// `isBeingDismissed` is whatever the test's dismissal says. Built through
/// ``AlarmFiringPresenter/makeFiringScreen`` so the presenter's own checks run
/// unchanged (#807).
///
/// It also records what it is asked to present, because after a swap the
/// mounted screen is the top of the hierarchy and the next swap's host.
class ReadBackFiringScreen: AlarmFiringViewController {
    weak var wiredPresenter: UIViewController?
    var dismissalInFlight = false
    private(set) var presentedScreens: [UIViewController] = []
    private(set) var dismissCalls = 0

    override var presentingViewController: UIViewController? { wiredPresenter }
    override var isBeingDismissed: Bool { dismissalInFlight }

    override func dismiss(animated flag: Bool, completion: (() -> Void)?) {
        dismissCalls += 1
    }

    override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        presentedScreens.append(screen)
        (screen as? ReadBackFiringScreen)?.wiredPresenter = self
    }
}

/// #807: the swap's gaps. A re-entry while `dismissStaleScreen` has not
/// reported back must neither dismiss the same screen twice nor put a second
/// firing screen up; a request parked in that window must still be raised; a
/// `present` UIKit declines in the completion must leave the alarm pending
/// and a line behind.
///
/// When UIKit runs the `dismiss(animated: false)` completion on a background
/// scene — synchronously or on a later turn — was not measured on a device.
/// The tests run both orderings instead, so the guard holds whichever it is.
@MainActor
final class AlarmFiringPresenterSwapGuardTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    /// A non-firing host. `accepts == false` is UIKit declining: the ask is
    /// recorded, the screen is not wired, and the read-back sees nothing.
    private final class Host: UIViewController {
        var accepts = true
        private(set) var presentedScreens: [UIViewController] = []
        private(set) var dismissCalls = 0

        override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
            presentedScreens.append(screen)
            if accepts { (screen as? ReadBackFiringScreen)?.wiredPresenter = self }
        }

        override func dismiss(animated flag: Bool, completion: (() -> Void)?) {
            dismissCalls += 1
        }
    }

    /// Something the stale firing screen presented itself: the top-up sheet,
    /// a refund alert, the WokeMorning summary left up after Stop.
    private final class Sheet: UIViewController {
        weak var presentedBy: UIViewController?
        override var presentingViewController: UIViewController? { presentedBy }
    }

    /// The top of the hierarchy, as the real walk would find it.
    private var top: UIViewController?
    /// What `top` becomes when an outstanding dismissal finishes; `nil` keeps it.
    private var topAfterDismissal: UIViewController?
    private var dismissed: [UIViewController] = []
    /// Outstanding dismissal completions, oldest first.
    private var completions: [() -> Void] = []
    private var lines: [Line] = []

    /// `synchronous` runs the dismissal completion inside the call, as UIKit
    /// may; otherwise the test runs it via `finishDismissal()`.
    /// `confirmsDismissal == false` is UIKit having dropped the dismissal: the
    /// screen never reads `isBeingDismissed`.
    private func makePresenter(
        alarms: [Alarm], synchronous: Bool = false, confirmsDismissal: Bool = true
    ) -> AlarmFiringPresenter {
        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
        let presenter = AlarmFiringPresenter(alarmRepository: .shared)
        presenter.locateHost = { [self] in
            guard let top = self.top else { return .failure(.noHostingWindow) }
            return .success(top)
        }
        presenter.makeFiringScreen = { ReadBackFiringScreen(alarm: $0, snoozeCount: $1) }
        presenter.isRootReady = { true }
        // Stands in for the repository fetch only, and resolves the id it is
        // given — a retry for one alarm must not raise another.
        presenter.mount = { [weak presenter] alarmID, count in
            guard let alarm = byID[alarmID] else { return false }
            return presenter?.present(alarm: alarm, snoozeCount: count) ?? false
        }
        presenter.dismissStaleScreen = { [self] screen, completion in
            self.dismissed.append(screen)
            let doubled = screen as? ReadBackFiringScreen
            if confirmsDismissal { doubled?.dismissalInFlight = true }
            let finish = { [self] in
                doubled?.dismissalInFlight = false
                if let next = self.topAfterDismissal { self.top = next }
                completion()
            }
            if synchronous { finish() } else { self.completions.append(finish) }
        }
        return presenter
    }

    private func finishDismissal() throws {
        XCTAssertFalse(completions.isEmpty, "test precondition: a dismissal has to be outstanding")
        guard !completions.isEmpty else { return }
        let completion = completions.removeFirst()
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: completion)
    }

    /// Lets the main queue run everything already enqueued on it.
    private func runOneMainQueueTurn() {
        let turn = expectation(description: "one main-queue turn")
        DispatchQueue.main.async { turn.fulfill() }
        wait(for: [turn], timeout: 10)
    }

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        super.tearDown()
    }

    // MARK: - Re-entry while the dismissal is outstanding

    func testReentry_whileTheDismissalIsOutstanding_neitherDismissesAgainNorStacks() throws {
        let alarm = Alarm()
        let stale = ReadBackFiringScreen(alarm: alarm)
        let host = Host()
        top = stale
        topAfterDismissal = host
        let presenter = makePresenter(alarms: [alarm])

        presenter.requestPresentation(alarmID: alarm.id)
        var answers: [Bool] = []
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: {
            presenter.flushPendingPresentation()
            answers.append(presenter.present(alarm: alarm))
        })

        XCTAssertEqual(dismissed.count, 1, "the re-entries dismissed the screen already being dismissed: \(dismissed)")
        XCTAssertEqual(answers, [false], "nothing is up yet, so the re-entry cannot answer true")
        XCTAssertTrue(stale.presentedScreens.isEmpty, "nothing may go up before the dismissal reports back")
        XCTAssertEqual(presenter.pendingAlarmID, alarm.id, "the alarm has to stay pending while nothing is up")
        let line = try XCTUnwrap(
            lines.first { $0.message.contains("still being dismissed") }, "the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(line.level, .default, "a deferral the swap will settle is a notice, not a failure")

        try finishDismissal()

        XCTAssertEqual(host.presentedScreens.count, 1, "exactly one firing screen goes up: \(host.presentedScreens)")
        XCTAssertNil(presenter.pendingPresentation, "the screen is up, nothing is left to retry")
    }

    /// Fix for round 2: parking for "the next activation" was no retry while
    /// the app stays foreground. The parked alarm is raised once the swap lands.
    func testReentry_forAnotherAlarmWhileTheDismissalIsOutstanding_isRaisedOnceTheSwapLands() throws {
        let first = Alarm()
        let second = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        topAfterDismissal = host
        let presenter = makePresenter(alarms: [first, second])

        _ = presenter.present(alarm: first)
        XCTAssertFalse(presenter.present(alarm: second, snoozeCount: 1))
        XCTAssertEqual(dismissed.count, 1, "the second alarm dismissed the screen already being dismissed")

        try finishDismissal()
        let firstScreen = try XCTUnwrap(
            host.presentedScreens.first as? ReadBackFiringScreen, "test precondition: the first alarm's screen went up"
        )
        top = firstScreen
        runOneMainQueueTurn()

        XCTAssertEqual(
            dismissed.count, 2,
            "the parked alarm was never re-attempted: while the app stays foreground nothing else raises it"
        )
        XCTAssertTrue(dismissed.last === firstScreen, "the follow-up swap has to take down the first alarm's screen")

        try finishDismissal()

        let secondScreen = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen)
        XCTAssertEqual(secondScreen.viewModel.alarm.id, second.id, "the screen raised has to be the parked alarm's")
        XCTAssertEqual(secondScreen.viewModel.snoozeCount, 1, "at the snooze count it was parked with (#808)")
        XCTAssertNil(presenter.pendingPresentation)
    }

    /// Taking the pending slot from another alarm loses that alarm, so the
    /// park line is an error then, whatever level the park itself logs at.
    func testReentry_whenParkingDisplacesAnotherAlarm_logsAnError() {
        let first = Alarm()
        let other = Alarm()
        let arriving = Alarm()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarms: [first, other, arriving])

        _ = presenter.present(alarm: first)
        presenter.requestPresentation(alarmID: other.id)
        XCTAssertEqual(presenter.pendingAlarmID, other.id, "test precondition: another alarm is parked")
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: {
            _ = presenter.present(alarm: arriving)
        })

        let line = lines.first { $0.message.contains("dropped") }
        XCTAssertEqual(line?.level, .error, "a lost alarm logged as a notice: \(lines.map(\.message))")
    }

    // MARK: - The marker's lifetime

    /// UIKit dropped the dismissal: the completion never comes and the screen
    /// is not being dismissed. A marker honoured anyway would refuse every
    /// later request for as long as that screen is up.
    func testReentry_whenUIKitDroppedTheDismissal_dismissesAgain() {
        let alarm = Alarm()
        let stale = ReadBackFiringScreen(alarm: Alarm())
        top = stale
        let presenter = makePresenter(alarms: [alarm], confirmsDismissal: false)

        _ = presenter.present(alarm: alarm)
        _ = presenter.present(alarm: alarm)

        XCTAssertEqual(
            dismissed.count, 2,
            "the marker outlived a dismissal UIKit is not performing, and the request waited on nothing"
        )
        XCTAssertTrue(stale.presentedScreens.isEmpty, "stacked on the stale screen")
    }

    /// Two swaps overlap: the first one's completion must not clear the
    /// marker the second one set.
    func testReentry_whenAnEarlierSwapReportsBackLate_stillParksOnTheCurrentOne() throws {
        let alarm = Alarm()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarms: [alarm])

        _ = presenter.present(alarm: alarm)
        let second = ReadBackFiringScreen(alarm: Alarm())
        top = second
        _ = presenter.present(alarm: alarm)
        XCTAssertEqual(dismissed.count, 2, "test precondition: the second swap started on the second screen")

        try finishDismissal()
        _ = presenter.present(alarm: alarm)

        XCTAssertEqual(dismissed.count, 2, "the first completion cleared the second swap's marker")
    }

    /// Completion run inside `dismissStaleScreen`, the ordering UIKit may use
    /// for a non-animated dismissal.
    func testSwap_whenTheCompletionRunsSynchronously_mountsOnceAndClearsThePendingAlarm() {
        let alarm = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        topAfterDismissal = host
        let presenter = makePresenter(alarms: [alarm], synchronous: true)

        presenter.requestPresentation(alarmID: alarm.id)

        XCTAssertEqual(dismissed.count, 1)
        XCTAssertEqual(host.presentedScreens.count, 1, "the swap has to mount once: \(host.presentedScreens)")
        XCTAssertNil(presenter.pendingPresentation, "the screen is up, so nothing is left to retry")
    }

    /// If the screen is still up after the dismissal reported back, the next
    /// request has to try again, in either ordering.
    func testSwap_afterTheDismissalReportsBack_aScreenStillUpIsDismissedAgain_inBothOrderings() throws {
        for synchronous in [true, false] {
            dismissed = []
            let alarm = Alarm()
            let stale = ReadBackFiringScreen(alarm: Alarm())
            top = stale
            let presenter = makePresenter(alarms: [alarm], synchronous: synchronous)

            _ = presenter.present(alarm: alarm)
            if !synchronous { try finishDismissal() }
            _ = presenter.present(alarm: alarm)

            XCTAssertEqual(dismissed.count, 2, "synchronous=\(synchronous): the next request never dismissed")
            XCTAssertTrue(stale.presentedScreens.isEmpty, "synchronous=\(synchronous): stacked on the stale screen")
        }
    }

    // MARK: - A firing screen already up when the completion runs

    /// The stale screen left the hierarchy before the completion ran, and a
    /// re-entry in that gap put this alarm's screen up directly.
    func testCompletion_whenThisAlarmsScreenIsAlreadyUp_doesNotStackASecond() throws {
        let alarm = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarms: [alarm])

        presenter.requestPresentation(alarmID: alarm.id)
        top = host
        XCTAssertTrue(presenter.present(alarm: alarm), "test precondition: the re-entry mounted directly")
        XCTAssertEqual(presenter.pendingAlarmID, alarm.id, "test precondition: the swap's request is still pending")
        let upAlready = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        top = upAlready
        try finishDismissal()

        XCTAssertTrue(upAlready.presentedScreens.isEmpty, "a second firing screen went up on the first")
        XCTAssertEqual(host.presentedScreens.count, 1)
        XCTAssertNil(presenter.pendingPresentation, "this alarm's screen is up; a pending record re-raises it")
        let line = lines.first { $0.message.contains("already up — not stacking") }
        XCTAssertEqual(line?.level, .default, "clearing the pending alarm left no line: \(lines.map(\.message))")
    }

    /// AlarmKit's swap at 0 is in flight when the notification path asks for
    /// the same alarm at 2, which parks. The count-0 mount must not wipe it.
    func testSwap_whenTheSameAlarmIsParkedAtAHigherCount_endsOnThatCount() throws {
        let alarm = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        topAfterDismissal = host
        let presenter = makePresenter(alarms: [alarm])

        presenter.requestPresentation(alarmID: alarm.id)
        _ = presenter.present(alarm: alarm, snoozeCount: 2)
        try finishDismissal()
        top = try XCTUnwrap(host.presentedScreens.last, "test precondition: the count-0 screen went up")
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 2),
            "the count-0 mount wiped the parked count-2 request (#808 class)"
        )

        runOneMainQueueTurn()
        try finishDismissal()

        let mounted = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen)
        XCTAssertEqual(mounted.viewModel.snoozeCount, 2, "the screen left up prices the next snooze from step 1")
        XCTAssertNil(presenter.pendingPresentation)
    }

    // MARK: - A stale screen that presented something itself

    /// `dismiss` sent to the stale screen itself takes down only what it
    /// presented. Staged here through the seam: the first dismissal pops the
    /// summary and leaves the screen. It must not then pass for this alarm's
    /// screen — the pending alarm would be cleared with nothing new on screen.
    func testSwap_whenTheStaleScreenSurvivesItsDismissal_stillRaisesTheNewScreen() throws {
        let alarm = Alarm()
        let host = Host()
        let stale = ReadBackFiringScreen(alarm: alarm)
        let summary = Sheet()
        summary.presentedBy = stale
        top = summary
        let presenter = makePresenter(alarms: [alarm])
        presenter.dismissStaleScreen = { [self] screen, completion in
            self.dismissed.append(screen)
            self.top = self.top === summary ? screen : (host as UIViewController)
            completion()
        }

        presenter.requestPresentation(alarmID: alarm.id)

        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 0),
            "the surviving stale screen was taken for this alarm's, and the request cleared with nothing new up"
        )
        XCTAssertTrue(stale.presentedScreens.isEmpty, "stacked on the stale screen")

        runOneMainQueueTurn()

        XCTAssertEqual(dismissed.count, 2, "the stale screen was not dismissed again")
        XCTAssertEqual(host.presentedScreens.count, 1, "the new firing screen never went up")
        XCTAssertNil(presenter.pendingPresentation)
    }

    /// A dismissal that reports back without removing anything must not
    /// re-swap on every main-queue turn: the stale-survival retry is bounded,
    /// and past the bound the request stays pending for the activation.
    func testSwap_whenTheDismissalNeverRemovesTheStaleScreen_retriesABoundedNumberOfTimes() {
        let alarm = Alarm()
        let stale = ReadBackFiringScreen(alarm: alarm)
        top = stale
        let presenter = makePresenter(alarms: [alarm])
        presenter.dismissStaleScreen = { [self] screen, completion in
            self.dismissed.append(screen)
            completion()
        }

        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: {
            presenter.requestPresentation(alarmID: alarm.id)
            for _ in 0..<10 { self.runOneMainQueueTurn() }
        })

        let limit = AlarmFiringPresenter.staleSurvivalRetryLimit
        XCTAssertEqual(
            dismissed.count, 1 + limit,
            "the retry spun instead of stopping at the bound: \(dismissed.count) dismissals"
        )
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 0),
            "past the bound the request must stay pending for the activation, not be dropped"
        )
        XCTAssertTrue(stale.presentedScreens.isEmpty, "stacked on the stale screen")
        XCTAssertEqual(
            lines.filter { $0.message.contains("still up after its dismissal") }.count, 1 + limit,
            "one line per attempt, and no more: \(lines.map(\.message))"
        )
    }

    /// The production dismissal goes to the stale screen's presenter, which
    /// takes the screen down together with anything it presented.
    func testSwap_sendsTheDismissalToTheStaleScreensPresenter() {
        let host = Host()
        let stale = ReadBackFiringScreen(alarm: Alarm())
        stale.wiredPresenter = host
        let summary = Sheet()
        summary.presentedBy = stale
        let presenter = AlarmFiringPresenter(alarmRepository: .shared)
        presenter.locateHost = { .success(summary) }
        presenter.makeFiringScreen = { ReadBackFiringScreen(alarm: $0, snoozeCount: $1) }
        // `dismissStaleScreen` left at its production default.

        _ = presenter.present(alarm: Alarm())

        XCTAssertEqual(stale.dismissCalls, 0, "sent to the stale screen, which only takes down what it presented")
        XCTAssertEqual(host.dismissCalls, 1, "the stale screen's presenter has to receive the dismissal")
    }

    /// The screen already up was built by AlarmKit's request, at 0, and the
    /// swap's own request carried 2. Calling that done prices the next snooze
    /// from the first step (#808).
    func testCompletion_whenThisAlarmIsUpAtALowerSnoozeCount_swapsItForTheCountedOne() throws {
        let alarm = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarms: [alarm])

        _ = presenter.present(alarm: alarm, snoozeCount: 2)
        top = host
        _ = presenter.present(alarm: alarm, snoozeCount: 0)
        let atZero = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        top = atZero
        try finishDismissal()

        XCTAssertTrue(atZero.presentedScreens.isEmpty, "a second firing screen went up on the first")
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 2),
            "the count-0 screen was taken for this one; the next snooze is priced from the first step"
        )

        runOneMainQueueTurn()
        XCTAssertTrue(dismissed.last === atZero, "the count-0 screen has to be swapped out")
        topAfterDismissal = host
        try finishDismissal()

        let mounted = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen)
        XCTAssertEqual(mounted.viewModel.snoozeCount, 2)
        XCTAssertNil(presenter.pendingPresentation)
    }

    /// The reverse: the screen up is at 2 and the swap's request is AlarmKit's
    /// 0. Swapping down would be the same reset, so it counts as done.
    func testCompletion_whenThisAlarmIsUpAtAHigherSnoozeCount_keepsIt() throws {
        let alarm = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarms: [alarm])

        presenter.requestPresentation(alarmID: alarm.id)
        top = host
        _ = presenter.present(alarm: alarm, snoozeCount: 2)
        top = try XCTUnwrap(host.presentedScreens.first)
        try finishDismissal()
        runOneMainQueueTurn()

        XCTAssertNil(presenter.pendingPresentation, "the count-2 screen is the right one; a (id, 0) record resets it")
        XCTAssertEqual(dismissed.count, 1, "the count-2 screen was swapped down to 0")
    }

    func testCompletion_whenAnotherAlarmsScreenIsAlreadyUp_keepsThisOnePendingAndSaysSo() throws {
        let alarm = Alarm()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarms: [alarm])

        _ = presenter.present(alarm: alarm, snoozeCount: 2)
        let other = ReadBackFiringScreen(alarm: Alarm())
        top = other
        try finishDismissal()

        XCTAssertTrue(other.presentedScreens.isEmpty, "a second firing screen went up on another alarm's")
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 2)
        )
        let line = try XCTUnwrap(lines.first { $0.message.contains("firing-present") }, "no line at all")
        XCTAssertTrue(line.message.contains("another firing screen went up"), "«\(line.message)»")
        XCTAssertEqual(line.level, .error)
    }

    // MARK: - Read-back

    /// Part 2: UIKit declines the `present` in the completion. Before #807
    /// the pending alarm was cleared right after the call, whatever it did.
    func testCompletion_whenUIKitDeclinesThePresent_keepsTheAlarmPendingAndLeavesALine() throws {
        let alarm = Alarm()
        let refusing = Host()
        refusing.accepts = false
        top = ReadBackFiringScreen(alarm: Alarm())
        topAfterDismissal = refusing
        let presenter = makePresenter(alarms: [alarm])

        presenter.requestPresentation(alarmID: alarm.id)
        try finishDismissal()

        XCTAssertEqual(refusing.presentedScreens.count, 1, "test precondition: the host was asked")
        XCTAssertEqual(
            presenter.pendingAlarmID, alarm.id,
            "the screen never went up; dropping the pending alarm leaves nothing to retry with (#798's shape)"
        )
        let line = try XCTUnwrap(lines.first { $0.message.contains("firing-present") }, "no line at all")
        XCTAssertTrue(
            line.message.contains("Host is not in the window hierarchy"),
            "the line has to carry why UIKit declined: «\(line.message)»"
        )
        XCTAssertTrue(line.message.contains("keeping it pending"), "«\(line.message)»")
        XCTAssertEqual(line.level, .error)
        XCTAssertEqual(line.category, .appDelegate)
    }
}
