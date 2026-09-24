import os
import XCTest
@testable import SnoozePay

/// The branch where a firing screen is already up and gets swapped for a new
/// one: the old screen is dismissed, and the replacement goes up in the
/// dismissal completion.
///
/// That completion is the only part of `AlarmFiringPresenter` whose outcome
/// nothing carries back into `present(alarm:)`'s answer. It used to answer
/// `true` regardless — reporting a screen that was not up yet — and then mount
/// through `Self.topViewController()?`, an optional chain that presents nothing
/// once the window has gone. The two together lost the firing screen in
/// silence: no screen, no log line, and `attemptPendingPresentation` clearing
/// `pendingAlarmID` on the strength of that `true`, so no retry either (#798).
///
/// Staged through the seams rather than real UIKit: the host comes from
/// ``AlarmFiringPresenter/locateHost`` (the real walk reads
/// `UIApplication.shared.connectedScenes`, which a unit test cannot populate),
/// and the dismissal from ``AlarmFiringPresenter/dismissStaleScreen``, which
/// hands the test the completion as a value. Running it is this suite's
/// stand-in for "the dismissal finished", and holding it is the only way to
/// reach the state the bug lives in — the host gone by the time it runs.
@MainActor
final class AlarmFiringPresenterReentryTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    /// Records what it was asked to present instead of doing it. The questions
    /// this suite has are "which controller was asked, and when" — mounting on
    /// a real detached controller would drag a UIKit presentation into a unit
    /// test to learn nothing more.
    ///
    /// It does answer the one thing the swap reads back (#807): the screen it
    /// accepted reports it as its presenter, as UIKit's would. Without that the
    /// read-back takes every mount here for a refusal.
    private final class RecordingHost: UIViewController {
        private(set) var presentedScreens: [UIViewController] = []

        override func present(
            _ viewControllerToPresent: UIViewController,
            animated flag: Bool,
            completion: (() -> Void)?
        ) {
            presentedScreens.append(viewControllerToPresent)
            (viewControllerToPresent as? ReadBackFiringScreen)?.wiredPresenter = self
        }
    }

    /// The same recorder in the role of the screen already on display. It has
    /// to BE an `AlarmFiringViewController`, since that type check is what
    /// `presentedFiringScreen(from:)` makes and therefore the entry condition
    /// of the whole branch.
    private final class RecordingFiringScreen: AlarmFiringViewController {
        private(set) var presentedScreens: [UIViewController] = []

        override func present(
            _ viewControllerToPresent: UIViewController,
            animated flag: Bool,
            completion: (() -> Void)?
        ) {
            presentedScreens.append(viewControllerToPresent)
        }
    }

    /// What the swap handed to `dismissStaleScreen`, kept so the test decides
    /// when the dismissal "finishes".
    private struct Dismissal {
        var screens: [UIViewController] = []
        var completion: (() -> Void)?
    }

    private var dismissal = Dismissal()

    private func makePresenter(host stale: UIViewController) -> AlarmFiringPresenter {
        let presenter = AlarmFiringPresenter(alarmRepository: .shared)
        presenter.locateHost = { .success(stale) }
        presenter.makeFiringScreen = { ReadBackFiringScreen(alarm: $0, snoozeCount: $1) }
        presenter.dismissStaleScreen = { [self] screen, completion in
            dismissal.screens.append(screen)
            dismissal.completion = completion
        }
        return presenter
    }

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        super.tearDown()
    }

    /// The synchronous half: the swap has been started, nothing is on screen
    /// yet, and that is what the return value has to say.
    func testReentry_whileTheDismissalIsStillOutstanding_doesNotReportAScreenItHasNotRaised() {
        let stale = RecordingFiringScreen(alarm: Alarm())
        let presenter = makePresenter(host: stale)

        let mounted = presenter.present(alarm: Alarm())

        XCTAssertEqual(
            dismissal.screens.count, 1,
            """
            test precondition: the swap has to be the branch that ran, or the \
            answer below is about some other path. It dismissed \
            \(dismissal.screens)
            """
        )
        XCTAssertTrue(
            dismissal.screens.first === stale,
            "the screen taken down has to be the one that was up, not the replacement"
        )
        XCTAssertTrue(
            stale.presentedScreens.isEmpty,
            "nothing can be mounted before the dismissal finishes — that is why the swap has a completion at all"
        )
        XCTAssertFalse(
            mounted,
            """
            the replacement goes up in the dismissal completion, which has not \
            run: answering true reports a screen that is not on screen, and the \
            caller drops the pending alarm on it (#798)
            """
        )
    }

    /// End to end through the path that reads the answer: request → swap → the
    /// screen actually goes up → only then is the alarm no longer pending.
    func testReentry_throughThePendingPath_keepsTheAlarmPendingUntilTheScreenIsUp() throws {
        let alarm = Alarm()
        // Another alarm's: this alarm's ringing screen is kept, not swapped (#835).
        let stale = RecordingFiringScreen(alarm: Alarm())
        let presenter = makePresenter(host: stale)
        presenter.isRootReady = { true }
        // Stands in for the repository fetch only: `present(alarmID:)` resolves
        // the model and hands off to `present(alarm:)`, which is the code under
        // test and runs for real here.
        presenter.mount = { [weak presenter] _, snoozeCount in
            presenter?.present(alarm: alarm, snoozeCount: snoozeCount) ?? false
        }

        presenter.requestPresentation(alarmID: alarm.id)

        XCTAssertEqual(dismissal.screens.count, 1, "test precondition: the swap has to have run")
        XCTAssertEqual(
            presenter.pendingAlarmID, alarm.id,
            """
            the swap has not finished, so the alarm has to stay pending: \
            reporting success before the screen is up leaves nothing to retry \
            with when it never goes up (#798)
            """
        )

        let newHost = RecordingHost()
        presenter.locateHost = { .success(newHost) }
        try XCTUnwrap(dismissal.completion)()

        XCTAssertEqual(
            newHost.presentedScreens.count, 1,
            """
            the replacement has to go up on the host resolved AFTER the \
            dismissal — re-resolving is the point of doing it in the \
            completion. It presented \(newHost.presentedScreens), and the host \
            from before the dismissal got \(stale.presentedScreens)
            """
        )
        XCTAssertTrue(
            newHost.presentedScreens.first is AlarmFiringViewController,
            "the screen mounted has to be the firing screen"
        )
        XCTAssertNil(
            presenter.pendingAlarmID,
            "with the screen up there is nothing left to retry, and a stale pending id re-raises it later"
        )
    }

    /// The state the bug lives in: by the time the dismissal finishes there is
    /// nowhere to present. The old screen is already gone, so this is a user
    /// with a ringing alarm and nothing on screen.
    func testReentry_whenTheHostIsGoneOnceTheDismissalFinishes_leavesALineAndArmsTheRetry() throws {
        let alarm = Alarm()
        let stale = RecordingFiringScreen(alarm: Alarm())
        let presenter = makePresenter(host: stale)

        // Real audio, not a stand-in, for the reason
        // `AlarmFiringPresenterDropTests` gives: `stopAlarmSound()` is a no-op
        // on a stopped service, so "still ringing" asserted from a silent start
        // would pass with a `stopAlarmSound()` added to this branch.
        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(AudioService.shared.isPlaying, "test precondition: the alarm has to be audible")
        XCTAssertNil(presenter.pendingAlarmID, "test precondition: nothing is pending yet")

        _ = presenter.present(alarm: alarm)
        presenter.locateHost = { .failure(.noHostingWindow) }

        let finishDismissal = try XCTUnwrap(dismissal.completion)
        var lines: [Line] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            finishDismissal()
        })

        XCTAssertTrue(
            stale.presentedScreens.isEmpty,
            "with no host there is nothing to mount on; falling back to the dismissed screen would mount into nowhere"
        )
        XCTAssertEqual(
            presenter.pendingAlarmID, alarm.id,
            """
            the screen never went up, so it has to be pending for the \
            scene-active retry (#382): this is the alarm the user is sleeping \
            through, and nothing else will raise it
            """
        )
        XCTAssertTrue(
            AudioService.shared.isPlaying,
            """
            the retry is armed and nothing is torn down, so this branch leaves \
            the audio alone — unlike the direct host miss in `present`, which \
            arms the same retry but stops the audio
            """
        )

        guard let line = lines.first(where: { $0.message.contains("firing-present") }) else {
            return XCTFail(
                """
                the drop left no line the suite can read. Nothing else records \
                it: the previous screen was dismissed, so the app looks exactly \
                as if no alarm had fired. The sink saw \(lines.map(\.message))
                """
            )
        }
        XCTAssertTrue(
            line.message.contains(ActiveWindowLocator.Miss.noHostingWindow.rawValue),
            "the line has to carry the locator's reason; it reads «\(line.message)»"
        )
        XCTAssertEqual(line.level, .error, "an alarm with no screen is a failure, not a notice")
        XCTAssertEqual(line.category, .appDelegate, "the category a support grep for the firing path filters by")
        XCTAssertFalse(line.message.contains("dropped"), "nothing else was pending: «\(line.message)»")
    }

    /// A swap for one alarm must not answer for another. The notification path
    /// calls `present(alarm:)` directly, and it can land while a different
    /// alarm sits pending from AlarmKit (#382) — clearing that one would drop
    /// the very screen this fix exists to keep.
    ///
    /// Since #835 the swap parks its own request before dismissing, and a
    /// deferral already in the slot loses to it (newest wins). So the other
    /// alarm is deferred while the swap is in flight: AlarmKit's request
    /// landing on a dismissal the notification path started.
    func testReentry_forADifferentAlarmThanThePendingOne_leavesThatDeferralAlone() throws {
        let deferred = UUID()
        let arriving = Alarm()
        let stale = RecordingFiringScreen(alarm: Alarm())
        let presenter = makePresenter(host: stale)
        presenter.isRootReady = { true }
        presenter.mount = { _, _ in false }

        _ = presenter.present(alarm: arriving)
        presenter.requestPresentation(alarmID: deferred)
        XCTAssertEqual(presenter.pendingAlarmID, deferred, "test precondition: the other alarm is pending")
        XCTAssertNotEqual(deferred, arriving.id, "test precondition: the two alarms have to differ")

        let newHost = RecordingHost()
        presenter.locateHost = { .success(newHost) }
        try XCTUnwrap(dismissal.completion)()

        XCTAssertEqual(
            newHost.presentedScreens.count, 1,
            "test precondition: the arriving screen has to have gone up, or there is nothing to clear on"
        )
        XCTAssertEqual(
            presenter.pendingAlarmID, deferred,
            "mounting one alarm's screen must not cancel another alarm's deferred one"
        )
    }

    /// The same alarm, deferred by AlarmKit at count 0 and then shown by the
    /// notification path at 2: the screen that went up is the pending one, so
    /// the record has to go. Clearing only on an exact `(id, count)` match —
    /// the refactor `Equatable` invites — would keep `(id, 0)` and re-mount it
    /// at 0 on the next activation, the price reset #808 closes.
    func testReentry_forTheAlarmAlreadyPendingAtAnotherCount_clearsIt() throws {
        let alarm = Alarm()
        let stale = RecordingFiringScreen(alarm: alarm)
        let presenter = makePresenter(host: stale)
        presenter.isRootReady = { true }
        presenter.mount = { _, _ in false }

        presenter.requestPresentation(alarmID: alarm.id)
        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 0),
            "test precondition: AlarmKit's deferral, at the count AlarmKit passes"
        )

        _ = presenter.present(alarm: alarm, snoozeCount: 2)
        let newHost = RecordingHost()
        presenter.locateHost = { .success(newHost) }
        try XCTUnwrap(dismissal.completion)()

        XCTAssertEqual(
            newHost.presentedScreens.count, 1,
            "test precondition: the count-2 screen has to have gone up, or there is nothing to clear on"
        )
        XCTAssertNil(
            presenter.pendingPresentation,
            "this alarm's screen is up; a leftover (id, 0) re-mounts it at the first step's price"
        )
    }

    /// The pending slot holds one alarm. When a different alarm was waiting in
    /// it, the swap takes the slot and that alarm's retry is gone: the line has
    /// to say so, once, naming it. Since #835 that is the swap's own line,
    /// written as it parks before dismissing; the host miss after it re-arms
    /// the same record and drops nothing more.
    func testReentry_whenTheHostIsGoneWhileAnotherAlarmWasPending_saysThatDeferralIsDropped() throws {
        let deferred = UUID()
        let arriving = Alarm()
        let stale = RecordingFiringScreen(alarm: Alarm())
        let presenter = makePresenter(host: stale)
        presenter.isRootReady = { true }
        presenter.mount = { _, _ in false }

        presenter.requestPresentation(alarmID: deferred)
        XCTAssertEqual(presenter.pendingAlarmID, deferred, "test precondition: the other alarm is pending")

        var lines: [Line] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            _ = presenter.present(alarm: arriving)
        })
        presenter.locateHost = { .failure(.noHostingWindow) }
        let finishDismissal = try XCTUnwrap(dismissal.completion)
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            finishDismissal()
        })

        let drops = lines.filter { $0.message.contains("another alarm's pending screen is dropped") }
        XCTAssertEqual(drops.count, 1, "the other alarm lost its retry, said once: \(lines.map(\.message))")
        XCTAssertEqual(drops.first?.level, .error)
        XCTAssertTrue(
            drops.first?.message.contains(String(deferred.uuidString.prefix(8))) ?? false,
            "the line has to name the alarm it dropped: \(lines.map(\.message))"
        )
        XCTAssertEqual(presenter.pendingAlarmID, arriving.id, "the swap's own request is what stays parked")
    }

    /// The #798 path itself: AlarmKit defers the alarm, the swap runs, and no
    /// host is left. The alarm in the slot is the one being re-armed, so
    /// nothing was dropped — a line claiming otherwise sends support after an
    /// alarm that does not exist.
    func testReentry_whenTheHostIsGoneForThePendingAlarmItself_dropsNothing() throws {
        let alarm = Alarm()
        let stale = RecordingFiringScreen(alarm: Alarm())
        let presenter = makePresenter(host: stale)
        presenter.isRootReady = { true }
        presenter.mount = { [weak presenter] _, snoozeCount in
            presenter?.present(alarm: alarm, snoozeCount: snoozeCount) ?? false
        }

        presenter.requestPresentation(alarmID: alarm.id)
        XCTAssertEqual(presenter.pendingAlarmID, alarm.id, "test precondition: this alarm is the pending one")

        presenter.locateHost = { .failure(.noHostingWindow) }
        let finishDismissal = try XCTUnwrap(dismissal.completion)
        var lines: [Line] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            finishDismissal()
        })

        XCTAssertEqual(presenter.pendingAlarmID, alarm.id, "the retry has to stay armed for this alarm")
        let line = try XCTUnwrap(
            lines.first { $0.message.contains("firing-present") },
            "the drop left no line; the sink saw \(lines.map(\.message))"
        )
        XCTAssertFalse(line.message.contains("dropped"), "the pending alarm is this one: «\(line.message)»")
    }

    /// The notification path hands `present(alarm:)` a snooze count, and when
    /// the swap finds no host the retry it arms is the only thing that will
    /// raise that screen again. The screen prices the next snooze as
    /// `penalty(forSnoozeCount: snoozeCount + 1)`, so a retry rebuilt at `0`
    /// bills a third snooze at the first step's price (#808).
    func testReentry_whenTheHostIsGoneOnceTheDismissalFinishes_retriesAtTheSnoozeCountItWasGiven() throws {
        let alarm = Alarm()
        let stale = RecordingFiringScreen(alarm: alarm)
        let presenter = makePresenter(host: stale)
        presenter.isRootReady = { true }
        // Stands in for the repository fetch only, as in the pending-path test
        // above: the snooze count the retry passes is what reaches the screen.
        presenter.mount = { [weak presenter] _, snoozeCount in
            presenter?.present(alarm: alarm, snoozeCount: snoozeCount) ?? false
        }

        _ = presenter.present(alarm: alarm, snoozeCount: 2)
        presenter.locateHost = { .failure(.noHostingWindow) }
        try XCTUnwrap(dismissal.completion)()

        XCTAssertEqual(
            presenter.pendingPresentation,
            AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: 2),
            "the retry has to be armed with the snooze count the screen was built with, not just its alarm"
        )

        let newHost = RecordingHost()
        presenter.locateHost = { .success(newHost) }
        presenter.flushPendingPresentation()

        let mounted = try XCTUnwrap(
            newHost.presentedScreens.first as? AlarmFiringViewController,
            "test precondition: the retry has to raise the firing screen; the host got \(newHost.presentedScreens)"
        )
        XCTAssertEqual(
            mounted.viewModel.snoozeCount, 2,
            "the retried screen restarted the snooze ladder — the next snooze is priced from the first step (#808)"
        )
        XCTAssertNil(presenter.pendingAlarmID, "the screen is up, so nothing is left to retry")
    }
}
