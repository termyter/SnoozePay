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
        // Since #833 the direct mount clears this alarm's record itself; what
        // is left to pin here is that the completion does not stack.
        XCTAssertNil(presenter.pendingPresentation, "the direct mount left the swap's request pending")
        let upAlready = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        top = upAlready
        try finishDismissal()

        XCTAssertTrue(upAlready.presentedScreens.isEmpty, "a second firing screen went up on the first")
        XCTAssertEqual(host.presentedScreens.count, 1)
        XCTAssertNil(presenter.pendingPresentation, "this alarm's screen is up; a pending record re-raises it")
        let line = lines.first { $0.message.contains("already up — not stacking") }
        XCTAssertEqual(line?.level, .default, "declining to stack left no line: \(lines.map(\.message))")
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
        XCTAssertTrue(line.message.contains("after dismissing"), "which path declined? «\(line.message)»")
        XCTAssertEqual(line.level, .error)
        XCTAssertEqual(line.category, .appDelegate)
    }

    // MARK: - The direct present (#833)

    /// No firing screen is up, so `present` mounts directly — the common path.
    /// It answered `true` without a read-back, so a declined present lost the
    /// alarm with no line of ours.
    func testDirect_whenUIKitDeclinesThePresent_keepsTheAlarmPendingAndLeavesALine() throws {
        let alarm = Alarm()
        let refusing = Host()
        refusing.accepts = false
        top = refusing
        let presenter = makePresenter(alarms: [alarm])
        // Real audio: `stopAlarmSound()` is a no-op on a stopped service.
        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(AudioService.shared.isPlaying, "test precondition: the alarm has to be audible")

        var answer = true
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: {
            answer = presenter.present(alarm: alarm, snoozeCount: 2)
        })

        XCTAssertEqual(refusing.presentedScreens.count, 1, "test precondition: the host was asked")
        XCTAssertTrue(dismissed.isEmpty, "test precondition: this is the direct path, not the swap")
        XCTAssertFalse(answer, "nothing is up; answering true tells the pending path to drop the alarm")
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 2),
            "the declined screen has to wait for the next activation, at the count it was built with (#808)"
        )
        XCTAssertTrue(AudioService.shared.isPlaying, "the retry is armed, so this is not the give-up branch")
        let line = try XCTUnwrap(lines.first { $0.message.contains("firing-present") }, "no line at all")
        XCTAssertTrue(
            line.message.contains("Host is not in the window hierarchy"),
            "the line has to carry why UIKit declined: «\(line.message)»"
        )
        XCTAssertFalse(line.message.contains("after dismissing"), "nothing was dismissed: «\(line.message)»")
        XCTAssertTrue(line.message.contains("keeping it pending"), "«\(line.message)»")
        XCTAssertEqual(line.level, .error)
        XCTAssertEqual(line.category, .appDelegate)

        // The refusal waits for the activation; it must not re-ask on its own.
        let linesBefore = lines.count
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: {
            for _ in 0..<3 { self.runOneMainQueueTurn() }
        })
        XCTAssertEqual(refusing.presentedScreens.count, 1, "a declined present was re-attempted on its own")
        XCTAssertEqual(
            lines.count, linesBefore, "new lines after the refusal: \(lines.dropFirst(linesBefore).map(\.message))"
        )
    }

    /// The same refusal reached through the AlarmKit retry, which drops its
    /// record on `true`, and the retry landing once the host accepts.
    func testDirect_throughThePendingPath_whenDeclined_retriesOnTheNextFlush() throws {
        let alarm = Alarm()
        let host = Host()
        host.accepts = false
        top = host
        let presenter = makePresenter(alarms: [alarm])

        presenter.requestPresentation(alarmID: alarm.id, snoozeCount: 1)

        XCTAssertEqual(host.presentedScreens.count, 1, "test precondition: the host was asked")
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 1),
            "the declined alarm was dropped: nothing will raise it again"
        )

        host.accepts = true
        presenter.flushPendingPresentation()

        let mounted = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen)
        XCTAssertTrue(mounted.presentingViewController === host, "the retry has to put the screen up")
        XCTAssertEqual(mounted.viewModel.snoozeCount, 1)
        XCTAssertNil(presenter.pendingPresentation)
    }

    /// AlarmKit deferred the alarm at 0, the notification path then shows it
    /// at 2 directly. The leftover `(id, 0)` would re-mount it at 0 on the
    /// next activation (#808).
    func testDirect_forTheAlarmPendingAtALowerCount_clearsIt() {
        let alarm = Alarm()
        let host = Host()
        let presenter = makePresenter(alarms: [alarm])
        presenter.isRootReady = { false }
        presenter.requestPresentation(alarmID: alarm.id)
        XCTAssertEqual(presenter.pendingAlarmID, alarm.id, "test precondition: AlarmKit's deferral at 0")
        top = host

        XCTAssertTrue(presenter.present(alarm: alarm, snoozeCount: 2))

        XCTAssertNil(presenter.pendingPresentation, "the (id, 0) record survived the count-2 screen going up")
        XCTAssertEqual(host.presentedScreens.count, 1)
    }

    /// The reverse: the record is at the HIGHER count. It stays, and is swapped
    /// in on the next turn rather than on an activation that may be hours off.
    func testDirect_forTheAlarmPendingAtAHigherCount_keepsItAndSwapsItIn() throws {
        let alarm = Alarm()
        let host = Host()
        var rootReady = false
        let presenter = makePresenter(alarms: [alarm])
        presenter.isRootReady = { rootReady }
        presenter.requestPresentation(alarmID: alarm.id, snoozeCount: 2)
        rootReady = true
        top = host

        XCTAssertTrue(presenter.present(alarm: alarm, snoozeCount: 0))
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 2),
            "the count-0 screen wiped the count-2 record; the next snooze is priced from step 1"
        )
        let atZero = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        top = atZero
        topAfterDismissal = host

        runOneMainQueueTurn()
        XCTAssertTrue(dismissed.first === atZero, "the count-2 record was never re-attempted")
        try finishDismissal()

        let mounted = try XCTUnwrap(host.presentedScreens.last as? ReadBackFiringScreen)
        XCTAssertEqual(mounted.viewModel.snoozeCount, 2)
        XCTAssertNil(presenter.pendingPresentation)
    }

    /// Another alarm deferred by AlarmKit is older than this one, which went up
    /// with nothing mid-swap. It is not cleared, and not raised over the fresh
    /// screen either: that swap stops the newer alarm's sound for the older
    /// one's screen. It waits for the next activation. (The converse — this
    /// alarm pending at a higher count IS raised — is the test above.)
    func testDirect_whileAnotherAlarmIsPending_leavesItParkedForTheActivation() throws {
        let deferred = Alarm()
        let arriving = Alarm()
        let host = Host()
        var rootReady = false
        let presenter = makePresenter(alarms: [deferred, arriving])
        presenter.isRootReady = { rootReady }
        presenter.requestPresentation(alarmID: deferred.id)
        rootReady = true
        top = host

        XCTAssertTrue(presenter.present(alarm: arriving))
        let arrivingScreen = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        top = arrivingScreen
        for _ in 0..<3 { runOneMainQueueTurn() }

        XCTAssertTrue(dismissed.isEmpty, "the older alarm was swapped in over the fresh screen: \(dismissed)")
        XCTAssertEqual(host.presentedScreens.count, 1)
        XCTAssertEqual(arrivingScreen.viewModel.alarm.id, arriving.id)
        XCTAssertEqual(presenter.pendingAlarmID, deferred.id, "mounting one alarm cancelled another's deferral")
    }

    // MARK: - Review round 2

    /// The already-up branch's own clear. A request for this alarm deferred
    /// (root not ready) after its screen went up directly, at a count below
    /// the screen's but above the swap's: only a clear by the count on screen
    /// drops it. By the swap's count it would stay and re-mount the alarm at 1
    /// over the screen at 2 (#808).
    func testCompletion_whenThisAlarmIsUpAndPendingAgain_clearsByTheShownCount() throws {
        let alarm = Alarm()
        let host = Host()
        var rootReady = true
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarms: [alarm])
        presenter.isRootReady = { rootReady }

        _ = presenter.present(alarm: alarm, snoozeCount: 0)
        top = host
        XCTAssertTrue(presenter.present(alarm: alarm, snoozeCount: 2), "test precondition: mounted directly")
        let upAtTwo = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        rootReady = false
        presenter.requestPresentation(alarmID: alarm.id, snoozeCount: 1)
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 1),
            "test precondition: the deferred request, between the swap's count and the screen's"
        )
        top = upAtTwo
        try finishDismissal()

        XCTAssertTrue(upAtTwo.presentedScreens.isEmpty, "a second firing screen went up on the first")
        XCTAssertNil(
            presenter.pendingPresentation,
            "the (id, 1) record outlived the count-2 screen: not cleared, or cleared by the swap's count 0"
        )
    }

    /// A screen going up refills the stale-survival budget, at both places one
    /// can: `presentReadingBack` (reached directly here; the swap's success
    /// shares it) and the already-up branch for this alarm. Without the reset
    /// the next stale screen gets one attempt instead of 1 + limit.
    func testSwap_aScreenGoingUpRefillsTheStaleSurvivalBudget() {
        let limit = AlarmFiringPresenter.staleSurvivalRetryLimit
        for throughAlreadyUp in [false, true] {
            let label = throughAlreadyUp ? "already-up branch" : "direct present"
            let alarm = Alarm()
            let presenter = makePresenter(alarms: [alarm])
            XCTAssertEqual(exhaustStaleSurvival(presenter, alarm: alarm), 1 + limit, "\(label): test precondition")

            if throughAlreadyUp {
                let upAlready = ReadBackFiringScreen(alarm: alarm)
                presenter.dismissStaleScreen = { [self] screen, completion in
                    self.dismissed.append(screen)
                    self.top = upAlready
                    completion()
                }
                lines = []
                AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: {
                    presenter.flushPendingPresentation()
                })
                XCTAssertTrue(
                    lines.contains { $0.message.contains("already up — not stacking") },
                    "\(label): test precondition: \(lines.map(\.message))"
                )
            } else {
                let host = Host()
                top = host
                presenter.flushPendingPresentation()
                XCTAssertEqual(host.presentedScreens.count, 1, "\(label): test precondition: the screen went up")
            }
            XCTAssertNil(presenter.pendingPresentation, "\(label): test precondition: the screen is up")

            XCTAssertEqual(
                exhaustStaleSurvival(presenter, alarm: alarm), 1 + limit,
                "\(label): the budget spent on the first stale screen was never refilled"
            )
        }
    }

    /// Stages a stale firing screen for `alarm` that no dismissal removes,
    /// requests the alarm and drains the bounded retries. Returns how many
    /// dismissals that took.
    private func exhaustStaleSurvival(_ presenter: AlarmFiringPresenter, alarm: Alarm) -> Int {
        dismissed = []
        top = ReadBackFiringScreen(alarm: alarm)
        presenter.dismissStaleScreen = { [self] screen, completion in
            self.dismissed.append(screen)
            completion()
        }
        presenter.requestPresentation(alarmID: alarm.id)
        for _ in 0..<(AlarmFiringPresenter.staleSurvivalRetryLimit + 3) { runOneMainQueueTurn() }
        return dismissed.count
    }
}
