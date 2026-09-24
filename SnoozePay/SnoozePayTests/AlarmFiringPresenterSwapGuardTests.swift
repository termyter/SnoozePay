import os
import XCTest
@testable import SnoozePay

/// A firing screen that answers the read-back the way UIKit does: its
/// `presentingViewController` is whoever accepted it. Built through
/// ``AlarmFiringPresenter/makeFiringScreen`` so the presenter's own
/// `firingVC.presentingViewController != nil` check runs unchanged (#807).
///
/// It also records what it is asked to present, because after a swap the
/// mounted screen is the top of the hierarchy and the next swap's host.
class ReadBackFiringScreen: AlarmFiringViewController {
    weak var wiredPresenter: UIViewController?
    private(set) var presentedScreens: [UIViewController] = []

    override var presentingViewController: UIViewController? { wiredPresenter }

    override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        presentedScreens.append(screen)
        (screen as? ReadBackFiringScreen)?.wiredPresenter = self
    }
}

/// #807: the swap's two gaps. A re-entry while `dismissStaleScreen` has not
/// reported back must neither dismiss the same screen twice nor put a second
/// firing screen up, and a `present` UIKit declines in the completion must
/// leave the alarm pending and a line behind.
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

        override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
            presentedScreens.append(screen)
            if accepts { (screen as? ReadBackFiringScreen)?.wiredPresenter = self }
        }
    }

    /// The top of the hierarchy, as the real walk would find it.
    private var top: UIViewController?
    private var dismissed: [UIViewController] = []
    private var pendingCompletion: (() -> Void)?
    private var lines: [Line] = []

    /// `synchronous` runs the dismissal completion inside the call, as UIKit
    /// may; otherwise the test runs it via `finishDismissal()`. `afterDismissal`
    /// is what the hierarchy's top becomes once the stale screen is gone.
    private func makePresenter(
        alarm: Alarm, synchronous: Bool = false, afterDismissal: (() -> UIViewController)? = nil
    ) -> AlarmFiringPresenter {
        let presenter = AlarmFiringPresenter(alarmRepository: .shared)
        presenter.locateHost = { [self] in
            guard let top = self.top else { return .failure(.noHostingWindow) }
            return .success(top)
        }
        presenter.makeFiringScreen = { ReadBackFiringScreen(alarm: $0, snoozeCount: $1) }
        presenter.isRootReady = { true }
        presenter.mount = { [weak presenter] _, count in
            presenter?.present(alarm: alarm, snoozeCount: count) ?? false
        }
        presenter.dismissStaleScreen = { [self] screen, completion in
            self.dismissed.append(screen)
            let finish = { [self] in
                if let afterDismissal { self.top = afterDismissal() }
                completion()
            }
            if synchronous { finish() } else { self.pendingCompletion = finish }
        }
        return presenter
    }

    private func finishDismissal() throws {
        let completion = try XCTUnwrap(pendingCompletion, "test precondition: a dismissal has to be outstanding")
        pendingCompletion = nil
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: completion)
    }

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        super.tearDown()
    }

    func testReentry_whileTheDismissalIsOutstanding_neitherDismissesAgainNorStacks() throws {
        let alarm = Alarm()
        let stale = ReadBackFiringScreen(alarm: alarm)
        let host = Host()
        top = stale
        let presenter = makePresenter(alarm: alarm, afterDismissal: { host })

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

    func testReentry_forAnotherAlarmWhileTheDismissalIsOutstanding_staysPendingPastTheMount() throws {
        let first = Alarm()
        let second = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarm: first, afterDismissal: { host })

        _ = presenter.present(alarm: first)
        XCTAssertFalse(presenter.present(alarm: second, snoozeCount: 1))
        try finishDismissal()

        XCTAssertEqual(dismissed.count, 1, "the second alarm dismissed the screen already being dismissed")
        XCTAssertEqual(host.presentedScreens.count, 1, "test precondition: the first alarm's screen went up")
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: second.id, snoozeCount: 1),
            "the alarm that arrived mid-swap is otherwise lost: nothing else will raise it"
        )
    }

    /// Completion run inside `dismissStaleScreen`, the ordering UIKit may use
    /// for a non-animated dismissal.
    func testSwap_whenTheCompletionRunsSynchronously_mountsOnceAndClearsThePendingAlarm() {
        let alarm = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarm: alarm, synchronous: true, afterDismissal: { host })

        presenter.requestPresentation(alarmID: alarm.id)

        XCTAssertEqual(dismissed.count, 1)
        XCTAssertEqual(host.presentedScreens.count, 1, "the swap has to mount once: \(host.presentedScreens)")
        XCTAssertNil(presenter.pendingPresentation, "the screen is up, so nothing is left to retry")
    }

    /// The marker must not outlive its completion in either ordering: if the
    /// screen is still up after the dismissal reported back, the next request
    /// has to try again, not wait on a dismissal that is over.
    func testSwap_afterTheDismissalReportsBack_aScreenStillUpIsDismissedAgain_inBothOrderings() throws {
        for synchronous in [true, false] {
            dismissed = []
            let alarm = Alarm()
            let stale = ReadBackFiringScreen(alarm: Alarm())
            top = stale
            let presenter = makePresenter(alarm: alarm, synchronous: synchronous)

            _ = presenter.present(alarm: alarm)
            if !synchronous { try finishDismissal() }
            _ = presenter.present(alarm: alarm)

            XCTAssertEqual(
                dismissed.count, 2,
                "synchronous=\(synchronous): the marker outlived its completion and the next request never dismissed"
            )
            XCTAssertTrue(stale.presentedScreens.isEmpty, "synchronous=\(synchronous): stacked on the stale screen")
        }
    }

    /// The stale screen left the hierarchy before the completion ran, and a
    /// re-entry in that gap put this alarm's screen up directly.
    func testCompletion_whenThisAlarmsScreenIsAlreadyUp_doesNotStackASecond() throws {
        let alarm = Alarm()
        let host = Host()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarm: alarm)

        _ = presenter.present(alarm: alarm)
        top = host
        XCTAssertTrue(presenter.present(alarm: alarm), "test precondition: the re-entry mounted directly")
        let upAlready = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        top = upAlready
        try finishDismissal()

        XCTAssertTrue(upAlready.presentedScreens.isEmpty, "a second firing screen went up on the first")
        XCTAssertEqual(host.presentedScreens.count, 1)
        XCTAssertNil(presenter.pendingPresentation, "this alarm's screen is up; a pending record re-raises it")
    }

    func testCompletion_whenAnotherAlarmsScreenIsAlreadyUp_keepsThisOnePendingAndSaysSo() throws {
        let alarm = Alarm()
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarm: alarm)

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

    /// Part 2: UIKit declines the `present` in the completion. Before #807
    /// the pending alarm was cleared right after the call, whatever it did.
    func testCompletion_whenUIKitDeclinesThePresent_keepsTheAlarmPendingAndLeavesALine() throws {
        let alarm = Alarm()
        let refusing = Host()
        refusing.accepts = false
        top = ReadBackFiringScreen(alarm: Alarm())
        let presenter = makePresenter(alarm: alarm, afterDismissal: { refusing })

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
