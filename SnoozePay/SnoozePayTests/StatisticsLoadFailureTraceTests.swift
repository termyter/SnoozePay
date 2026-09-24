import os
import UIKit
import XCTest
@testable import SnoozePay

/// The statistics load-failure path, end to end: what the user sees, and —
/// the part #721 is about — what the *developer* sees afterwards.
///
/// Every failure on this screen renders as an absence: no numbers, an all-dark
/// heatmap, a state column. That absence is byte-identical to a brand-new
/// install, so the log line is the only thing separating "this user has no
/// history" from "this user's ledger is damaged". Before #721 three of the
/// four failure exits produced no line at all:
///
///   1. a bare `catch` that swallowed every error that was not a
///      `RepositoryError` — no alert, no log;
///   2. `onLoadError?(…)`, which is `nil` until the VC binds, so an early
///      failure evaporated through the optional chain;
///   3. the `presentedViewController == nil` guard in the VC, which dropped
///      the second and every later error;
///   4. `presentRepositoryError`, which showed the user an alert and told the
///      log nothing.
///
/// So the assertions here are mostly about the trace, not the UI. `logLoadFailure`
/// is the seam that makes that assertable: the VM writes to a closure, so a
/// test can read what production sends to `AppLogger.repository`.
final class StatisticsLoadFailureTraceTests: XCTestCase {

    /// An error type the repository cannot produce, standing in for whatever
    /// reaches the non-`RepositoryError` branch next: a decoder error of
    /// another type, a `CancellationError`, a neighbouring call that starts
    /// throwing. The branch has no reachable production input today, which is
    /// exactly why it stayed empty for a year.
    private struct StubFailure: Error {}

    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var txRepo: TransactionRepository!
    private var wakeStore: WakeEventStore!

    private let calendar = StatisticsViewModel.mondayFirstCalendar

    override func setUp() {
        super.setUp()
        suiteName = "test.statsFailureTrace.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        wakeStore = WakeEventStore(defaults: testDefaults)
        txRepo = TransactionRepository(defaults: testDefaults, wakeStore: wakeStore)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeVM() -> StatisticsViewModel {
        StatisticsViewModel(
            repository: txRepo,
            wakeStore: wakeStore,
            defaults: testDefaults,
            calendar: calendar
        )
    }

    /// Puts a blob in the ledger slot that cannot decode — the one-line
    /// "repository configured to fail" this suite needs.
    private func corruptTheLedger() {
        testDefaults.set(Data("not json".utf8), forKey: "stored_transactions")
    }

    // MARK: - The ledger threw a RepositoryError

    /// The alert *and* the trace, asserted together. Removing the
    /// `onLoadError` hand-off reds the first half; removing the log call reds
    /// the second, because the collector is the only thing `logLoadFailure`
    /// writes to under test.
    func testCorruptLedger_alertsTheUserAndLeavesATrace() {
        corruptTheLedger()
        let viewModel = makeVM()
        var traces: [String] = []
        viewModel.logLoadFailure = { traces.append($0) }
        var receivedError: LocalizedError?
        viewModel.onLoadError = { receivedError = $0 }

        viewModel.loadData()

        guard let repositoryError = receivedError as? TransactionRepository.RepositoryError,
              case .decodeFailure = repositoryError else {
            XCTFail("expected a decodeFailure alert, got \(String(describing: receivedError))")
            return
        }
        XCTAssertEqual(traces.count, 1, "one failed read must leave exactly one line, not zero and not four")
        XCTAssertTrue(
            traces.first?.contains(StatisticsViewModel.ledgerUnreadableErrorID) == true,
            "the line must carry the grep handle a support ticket is followed by; it reads «\(traces.first ?? "")»"
        )
    }

    /// The optional-chaining hole. `bindViewModel()` runs in `viewDidLoad`, so
    /// a load that fails before then has no observer — and used to leave
    /// nothing behind at all. The line is now emitted regardless, and records
    /// that the alert was never shown, because "failed, user warned" and
    /// "failed, user told nothing" are different incidents.
    func testCorruptLedger_withNobodyBound_stillLeavesATrace() {
        corruptTheLedger()
        let viewModel = makeVM()
        var traces: [String] = []
        viewModel.logLoadFailure = { traces.append($0) }

        viewModel.loadData()

        XCTAssertEqual(traces.count, 1, "an unobserved failure is the one that most needs a log line")
        XCTAssertTrue(
            traces.first?.contains("Alert observer bound: false") == true,
            "the line must say the alert went nowhere; it reads «\(traces.first ?? "")»"
        )
    }

    // MARK: - The ledger threw something else

    /// What the bare `catch` used to absorb. Reached directly because nothing
    /// on the production path throws a non-`RepositoryError` today — a branch
    /// whose only defence is "this can't happen" is the branch that was empty.
    func testUnexpectedFailure_logsUnderItsOwnIDAndStillAlerts() {
        let viewModel = makeVM()
        var traces: [String] = []
        viewModel.logLoadFailure = { traces.append($0) }
        var receivedError: LocalizedError?
        viewModel.onLoadError = { receivedError = $0 }

        viewModel.handleLedgerLoadFailure(StubFailure())

        XCTAssertEqual(traces.count, 1, "the branch that used to be empty must now write exactly one line")
        XCTAssertTrue(
            traces.first?.contains(StatisticsViewModel.unexpectedLedgerErrorID) == true,
            "an unexpected throw needs its own grep handle, not the known one; it reads «\(traces.first ?? "")»"
        )
        XCTAssertTrue(
            traces.first?.contains("StubFailure") == true,
            "the underlying type is the whole diagnostic value of this line; it reads «\(traces.first ?? "")»"
        )
        XCTAssertTrue(
            receivedError is StatisticsViewModel.UnexpectedLedgerFailure,
            "an unknown failure still leaves the screen empty, so the user is told, not left guessing"
        )
        XCTAssertEqual(
            receivedError?.errorDescription, Localized.text("statistics.error.message"),
            "the alert body is the screen's own copy — a decoder's English debugDescription is not user copy"
        )
    }

    /// The state half of the same fix: an unexpected throw must withhold every
    /// ledger-derived figure exactly like a known one. Publishing an empty
    /// `charges` as if it were a clean history is the misreading #459 closed.
    func testUnexpectedFailure_withholdsEveryLedgerDerivedFigure() {
        let viewModel = makeVM()
        viewModel.logLoadFailure = { _ in }

        viewModel.handleLedgerLoadFailure(StubFailure())

        XCTAssertEqual(viewModel.ledgerUnavailableReason, .ledgerUnreadable)
        XCTAssertFalse(viewModel.ledgerReadable)
        XCTAssertTrue(viewModel.charges.isEmpty)
        XCTAssertEqual(viewModel.streak, 0)
    }

    // MARK: - "No data" must stay distinguishable from "broken data"

    /// The acceptance criterion the other tests can't state on their own: a
    /// healthy read is silent. If a successful load also wrote a line, the log
    /// would stop separating the two states and the trace would be worthless.
    func testHealthyLedger_writesNoFailureTrace() {
        txRepo.record(Transaction(type: .charge, amount: 50, createdAt: Date()))
        let viewModel = makeVM()
        var traces: [String] = []
        viewModel.logLoadFailure = { traces.append($0) }

        viewModel.loadData()

        XCTAssertTrue(traces.isEmpty, "a ledger that read fine must leave the log alone")
        XCTAssertTrue(viewModel.ledgerReadable)
    }

    /// A brand-new install: no rows, no failure. Same visual outcome as a
    /// corrupt ledger, opposite log — which is the entire point.
    func testEmptyLedger_writesNoFailureTrace() {
        let viewModel = makeVM()
        var traces: [String] = []
        viewModel.logLoadFailure = { traces.append($0) }

        viewModel.loadData()

        XCTAssertTrue(traces.isEmpty, "an empty history is not a failure and must not read as one")
        XCTAssertNil(viewModel.ledgerUnavailableReason)
    }
}

/// Returns from `present` having done nothing — which is all a caller ever
/// sees of a refusal UIKit does not publish.
private class StatsSwallowingHost: UIViewController {
    private(set) var wasAskedToPresent = false

    override func present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)? = nil
    ) {
        wasAskedToPresent = true
    }
}

/// Presenters answering `isBeingDismissed` / `isBeingPresented` with a
/// constant, the idiom `AppDelegateAlertTests` uses: a live transition would
/// put UIKit's flag timing under assertion instead of the branch. They also
/// swallow `present`, because the reason is asked for only after a refusal,
/// and a constant flag does not make UIKit refuse.
private final class StatsDismissingHost: StatsSwallowingHost {
    override var isBeingDismissed: Bool { true }
}

private final class StatsPresentingHost: StatsSwallowingHost {
    override var isBeingPresented: Bool { true }
}

/// A load error with a message the test chooses, so two held errors can be
/// told apart (#825). The repository's own errors all read the same.
private struct StatsStubLoadError: LocalizedError {
    let errorDescription: String?
}

/// A container that never forwards appearance to its child, so the test
/// decides exactly when `viewWillAppear` and `viewDidAppear` run (#825).
private final class StatsManualAppearanceHost: UIViewController {
    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
}

/// What `showHeldErrorThroughARealAppearance()` leaves behind for the
/// assertions.
private struct StatsMountedAppearance {
    let host: StatsManualAppearanceHost
    let stats: StatisticsViewController
    let ledger: UserDefaults
    let lines: [String]
}

/// The VC half: the alert the user actually gets, and the second one they
/// don't.
///
/// The seam needs no injection — `StatisticsViewController.viewModel` and
/// `StatisticsViewModel.onLoadError` are both internal and `bindViewModel()`
/// runs in `viewDidLoad`, so `loadViewIfNeeded()` plus a call through the
/// closure drives the real presentation path. The tests that need the real
/// `viewWillAppear` load itself to fail are the exception: they inject a view
/// model on a ledger of their own through `init(viewModel:)`
/// (`makeStatsOnOwnLedger`, #825).
///
/// The appearance cycle **does** run: `makeKeyAndVisible()` triggers it, so
/// `viewWillAppear` fires and with it a production `loadData()` against
/// `TransactionRepository.shared` / `UserDefaults.standard` — the same fact
/// `NavigationBarSymmetryTests` and `WalletLightThemeTests` write down for
/// their own windows. Harmless today, because nothing in this target writes a
/// corrupt `stored_transactions` into the standard defaults. The day something
/// does, that load would raise a *real* alert carrying this suite's expected
/// title and body, and both tests below would go green for the wrong reason —
/// which is what the preconditions in `makeMountedController()` turn red. Since
/// #825 such an error is held rather than presented, so the precondition reads
/// the held message as well as `presentedViewController`.
@MainActor
final class StatisticsLoadErrorAlertTests: XCTestCase {

    /// Held for the test's lifetime — a released window takes the controller
    /// under assertion with it.
    private var window: UIWindow!
    /// Restored in `tearDown`. A suite that takes key status and never hands
    /// it back leaves every later presentation aimed at a window nobody is
    /// looking at — the failure `UITourConfirmDeleteRouteTests` was burned by
    /// and which is open right now as #728.
    private var previousKeyWindow: UIWindow?

    override func setUp() {
        super.setUp()
        // This suite spins the main run loop to wait for a presentation, so it
        // would otherwise spend the backlog the ~1000 preceding synchronous
        // tests left queued inside its own wait (#618, #693).
        drainMainQueue()
        previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    override func tearDown() {
        window?.rootViewController?.dismiss(animated: false)
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        previousKeyWindow?.makeKeyAndVisible()
        previousKeyWindow = nil
        for name in ledgerSuiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        ledgerSuiteNames = []
        super.tearDown()
    }

    /// Suites made by `makeStatsOnOwnLedger(corrupt:)`, removed in `tearDown`.
    private var ledgerSuiteNames: [String] = []

    private func makeMountedController() -> StatisticsViewController {
        let controller = StatisticsViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        // Mounting runs the appearance cycle, and `viewWillAppear` loads the
        // real ledger. Anything on screen at this point came from that load,
        // not from the closure these tests drive.
        XCTAssertNil(
            controller.presentedViewController,
            "mounting already presented something — the assertions below would grade the wrong alert"
        )
        XCTAssertNil(
            controller.pendingLoadErrorMessage,
            "mounting already holds a load error — the real ledger is unreadable, and the assertions below would grade it"
        )
        return controller
    }

    private func decodeFailure() -> TransactionRepository.RepositoryError {
        .decodeFailure(underlying: NSError(domain: "test", code: 1))
    }

    /// Polls rather than sleeping: a presentation that never happens ends at
    /// the caller's assertion, which can name what is on screen, instead of at
    /// a bare "Asynchronous wait failed".
    private func waitForAlert(on controller: UIViewController) -> UIAlertController? {
        let presented = expectation(description: "load error alert presented")
        // 20 s to match the sibling presentation suites. The wait exists to
        // tell "this never presents" from "this presents late"; on a saturated
        // three-core runner a tight deadline answers "the runner was busy"
        // instead, and seconds shaved off a 214–333 s job buy nothing against
        // a flaky red.
        let deadline = Date().addingTimeInterval(20)
        func poll() {
            if controller.presentedViewController != nil || Date() >= deadline {
                presented.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
        }
        poll()
        wait(for: [presented], timeout: 25)
        return controller.presentedViewController as? UIAlertController
    }

    /// The last seam site that #731 could not observe (#742).
    ///
    /// ALERT-SHOWN is written from `present(_:animated:completion:)`'s
    /// completion, which runs a runloop turn AFTER the call returns. #731
    /// recorded that as something `withTestSink` "cannot see"; review corrected
    /// it, and the correction is what this test is built on: `perform` is
    /// synchronous, but nothing stops its BODY from turning the run loop, and
    /// the sink stays installed for the whole wait.
    ///
    /// ⚠️ It waits on the LINE, not on `presentedViewController`. The sibling
    /// `waitForAlert` returns as soon as UIKit sets that property — which
    /// happens inside `present`, before the completion runs — so a test built
    /// on it would sample the sink too early and pass or fail on timing.
    /// Waiting for the thing being asserted is also why this costs no more
    /// wall-clock than the poll it replaces: both end on the same presentation.
    func testFirstLoadError_logsThatTheUserActuallySawIt() {
        let controller = makeMountedController()
        let shown = expectation(description: "the ALERT-SHOWN line reached the seam")
        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        var fulfilled = false

        // Drained IMMEDIATELY before the sink goes in, not just in `setUp`.
        // #742 §2a warns that a sink which waits will catch a neighbour's
        // deferred ALERT-SHOWN — and unlike the ALERT-DROPPED test, filtering
        // by grep handle cannot save this one: the contaminant carries the
        // SAME id, so it would land in `shownLines` and break `count == 1`.
        // Without this the test is green only because XCTest runs the class
        // alphabetically and «_logs…» sorts before «_presents…», which is not
        // a property anyone should have to preserve when renaming a test.
        drainMainQueue()

        AppLogger.withTestSink({ category, level, message in
            lines.append((category, level, message))
            // Guarded: a second fulfil is an XCTest API misuse failure, and
            // this branch is reached again by any later ALERT-SHOWN.
            if !fulfilled, message.contains(StatisticsViewModel.alertShownErrorID) {
                fulfilled = true
                shown.fulfill()
            }
        }, perform: {
            controller.viewModel.onLoadError?(decodeFailure())
            // Before the wait: the post-present read-back runs synchronously
            // inside the call, so a DROPPED line for this alert — the symptom
            // of UIKit no longer wiring the alert's `presentingViewController`
            // inside `present` — would already be here (#790).
            XCTAssertTrue(
                lines.allSatisfy { !$0.message.contains(StatisticsViewModel.alertDroppedErrorID) },
                "the read-back after present must see the alert UIKit just put up; the sink saw \(lines.map(\.message))"
            )
            // 25 s to match `waitForAlert`: on a saturated three-core runner a
            // tight deadline answers "the runner was busy", not "it never logged".
            wait(for: [shown], timeout: 25)
        })

        let shownLines = lines.filter { $0.message.contains(StatisticsViewModel.alertShownErrorID) }
        XCTAssertEqual(
            shownLines.count, 1,
            "one shown alert must leave exactly one line; the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(shownLines.first?.category, .ui, "an alert the user saw is a screen-level event")
        XCTAssertEqual(shownLines.first?.level, .error, "the warning behind the alert is not a notice")
        XCTAssertTrue(
            shownLines.first?.message.contains(Localized.text("wallet.error.load_failed")) == true,
            "the line has to carry the sentence the user actually read, not just its grep handle; "
            + "it reads «\(shownLines.first?.message ?? "")»"
        )
        XCTAssertNotNil(
            controller.presentedViewController as? UIAlertController,
            "the line claims an alert was shown, so one has to be on screen"
        )
    }

    /// The first error reaches the user, with catalogue copy — the call-site
    /// coverage `statistics.error.title` never had (see
    /// `StatisticsScreensLocalizationTests`, which left it to #721).
    func testFirstLoadError_presentsAlertWithCatalogueCopy() {
        let controller = makeMountedController()

        controller.viewModel.onLoadError?(decodeFailure())

        let alert = waitForAlert(on: controller)
        XCTAssertNotNil(
            alert,
            """
            no alert came up for a ledger decode failure. \
            \(presentationDiagnostics(rootedAt: window.rootViewController))
            """
        )
        XCTAssertEqual(alert?.title, Localized.text("statistics.error.title"))
        XCTAssertEqual(
            alert?.message, Localized.text("wallet.error.load_failed"),
            "the repository's own description wins over the generic fallback"
        )
    }

    /// The second error must not stack a new alert — UIKit throws on that —
    /// but it must not disappear either. `droppedAlertDiagnostic` is the line
    /// the guard now writes, so what the guard would print is asserted here
    /// without staging a second presentation.
    func testSecondLoadError_keepsTheFirstAlertAndHasSomethingToLog() {
        let controller = makeMountedController()
        controller.viewModel.onLoadError?(decodeFailure())
        let firstAlert = waitForAlert(on: controller)
        XCTAssertNotNil(firstAlert, "test precondition: the first alert must be up")

        // Through the seam (#731), so this asserts the line was EMITTED, not
        // merely that `droppedAlertDiagnostic` can build one. Deleting the
        // `AppLogger.emit` in `presentRepositoryError` used to leave this whole
        // suite green: the guard still returned, the second error still
        // vanished, and the pure-function assertions below never noticed —
        // which is verbatim the #721 defect this test exists to close.
        //
        // No new wall-clock: this branch returns synchronously without
        // presenting, and the only wait in the test is the one already paid
        // above for the FIRST alert.
        //
        // Selected by grep handle rather than by `dropped.count`, deliberately.
        // `waitForAlert` polls `presentedViewController`, which UIKit sets
        // inside `present` — so it returns BEFORE the first alert's completion
        // runs, and that completion writes ALERT-SHOWN. Today that line cannot
        // land here only because `perform` never turns the run loop; add any
        // wait inside this closure and a count-based assertion would fail
        // pointing at the wrong line.
        var dropped: [(AppLogCategory, OSLogType, String)] = []
        AppLogger.withTestSink({ dropped.append(($0, $1, $2)) }, perform: {
            controller.viewModel.onLoadError?(decodeFailure())
        })

        XCTAssertTrue(
            controller.presentedViewController === firstAlert,
            "a second alert must not replace or stack on the first"
        )
        let dropLines = dropped.filter { $0.2.contains(StatisticsViewModel.alertDroppedErrorID) }
        XCTAssertEqual(
            dropLines.count, 1,
            "the dropped alert must leave exactly one ALERT-DROPPED line; the sink saw \(dropped.map(\.2))"
        )
        XCTAssertEqual(dropLines.first?.0, .ui, "a screen-level drop belongs to the UI category")
        XCTAssertEqual(dropLines.first?.1, .error, "a warning the user never saw is not a notice")
        // The production sentence rather than a literal: the line has to read
        // as the message the user did not get, and the test above already
        // pins that this is the message the alert carries.
        let unshownMessage = Localized.text("wallet.error.load_failed")
        let diagnostic = StatisticsViewController.droppedAlertDiagnostic(
            presenter: controller, message: unshownMessage
        )
        XCTAssertNotNil(diagnostic, "a dropped alert with no log line is the defect #721 is about")
        XCTAssertTrue(
            diagnostic?.contains(StatisticsViewModel.alertDroppedErrorID) == true,
            "a dropped warning needs its own grep handle; it reads «\(diagnostic ?? "")»"
        )
        XCTAssertTrue(
            diagnostic?.contains("UIAlertController") == true,
            "the line must name what blocked the alert; it reads «\(diagnostic ?? "")»"
        )
        // Ties the two halves together. Without it, `presentRepositoryError`
        // could emit a bare grep handle and the assertions above would still
        // pass: the ones on `dropLines` only look for the handle, and the ones
        // on `diagnostic` test a value this test built itself.
        XCTAssertEqual(
            dropLines.first?.2, diagnostic,
            "the emitted line must BE the diagnostic, not merely carry its handle"
        )
        XCTAssertTrue(
            diagnostic?.contains(unshownMessage) == true,
            "the unshown message is the part worth recovering; it reads «\(diagnostic ?? "")»"
        )
    }

    /// The other half of that guard: with nothing presented there is nothing
    /// to report, and the alert goes up. Without this the previous test would
    /// pass against a controller that logs on every error and never presents.
    func testNothingPresented_producesNoDropDiagnostic() {
        let host = UIViewController()
        attachToWindow(host)
        XCTAssertNil(
            StatisticsViewController.droppedAlertDiagnostic(presenter: host, message: "any"),
            "a free screen must present the alert, not log about dropping it"
        )
    }

    // MARK: - Refusals the "already presented" guard does not decide (#790)

    /// The refusal the read-back exists for: `present` asked of an off-window
    /// screen with no parent, which UIKit refuses with "not in the window
    /// hierarchy". Until #790 that left no alert AND no line.
    ///
    /// Calls `showLoadErrorAlert` directly. Since #825 the screen itself no
    /// longer presents while off-window: an error from `onLoadError` is held
    /// (see `testLoadErrorOffWindow_…`). The function still has to report a
    /// refusal from any presenter it is given, so this line is still pinned.
    func testShowingOnAnUnmountedScreen_leavesALineNamingTheWindow() {
        let controller = StatisticsViewController()
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.viewIfLoaded?.window, "test precondition: the screen must be off-window")
        XCTAssertNil(controller.parent, "test precondition: no ancestor UIKit could present through")
        let message = Localized.text("wallet.error.load_failed")

        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        AppLogger.withTestSink({ lines.append((category: $0, level: $1, message: $2)) }, perform: {
            StatisticsViewController.showLoadErrorAlert(on: controller, message: message)
        })

        let dropLines = lines.filter { $0.message.contains(StatisticsViewModel.alertDroppedErrorID) }
        XCTAssertEqual(
            dropLines.count, 1,
            "an off-window presenter must leave exactly one ALERT-DROPPED line; the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(dropLines.first?.category, .ui)
        XCTAssertEqual(dropLines.first?.level, .error)
        XCTAssertTrue(
            dropLines.first?.message.contains("StatisticsViewController is not in the window hierarchy") == true,
            "the line must name WHY; it reads «\(dropLines.first?.message ?? "")»"
        )
        XCTAssertTrue(
            dropLines.first?.message.contains(message) == true,
            "the unshown message is the part worth recovering; it reads «\(dropLines.first?.message ?? "")»"
        )
        XCTAssertEqual(
            dropLines.first?.message,
            StatisticsViewController.droppedAlertLine(
                reason: StatisticsViewController.refusalReason(presenter: controller),
                message: message
            ),
            "the emitted line must BE the refusal line, not merely carry its handle"
        )
        XCTAssertNil(controller.presentedViewController, "UIKit must have refused, or the line above lies")
    }

    // MARK: - An error that arrives before the screen is in the window (#825)

    /// An error that arrives while the view has no window is held, not
    /// presented. Presenting it would be a detached presentation, and not
    /// logging it is correct because nothing has been refused yet.
    ///
    /// A `viewDidAppear` run on an off-window controller must not show it
    /// either. The flush checks the window again rather than trusting the
    /// callback, and this is the only test that can tell those apart: in a
    /// real appearance the view is always in the window.
    func testLoadErrorOffWindow_isHeldNotPresentedAndLogsNothing() {
        let controller = StatisticsViewController()
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.viewIfLoaded?.window, "test precondition: the screen must be off-window")

        var lines: [String] = []
        AppLogger.withTestSink({ lines.append($2) }, perform: {
            controller.viewModel.onLoadError?(decodeFailure())
            controller.viewDidAppear(false)
        })

        XCTAssertEqual(
            controller.pendingLoadErrorMessage, Localized.text("wallet.error.load_failed"),
            "the error must wait for the screen, not be presented or thrown away"
        )
        XCTAssertNil(controller.presentedViewController, "nothing may be presented from an off-window screen")
        XCTAssertTrue(
            lines.allSatisfy {
                !$0.contains(StatisticsViewModel.alertShownErrorID)
                    && !$0.contains(StatisticsViewModel.alertDroppedErrorID)
            },
            "a held error is neither shown nor dropped yet; the sink saw \(lines)"
        )
    }

    /// Two errors before the screen appears: the first is kept, and the
    /// second is logged as dropped. That is the same order as the on-screen
    /// case, where the first alert stays up and the second gets the line
    /// (`testSecondLoadError_…`).
    ///
    /// Two different messages, so first-wins and last-wins give different
    /// results. With identical ones either choice would pass.
    func testSecondLoadErrorWhileHeld_keepsTheFirstAndLogsTheSecond() {
        let controller = StatisticsViewController()
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.viewIfLoaded?.window, "test precondition: the screen must be off-window")

        var lines: [String] = []
        AppLogger.withTestSink({ lines.append($2) }, perform: {
            controller.viewModel.onLoadError?(StatsStubLoadError(errorDescription: "first"))
            controller.viewModel.onLoadError?(StatsStubLoadError(errorDescription: "second"))
        })

        XCTAssertEqual(controller.pendingLoadErrorMessage, "first", "the first held error must be the one shown")
        let dropLines = lines.filter { $0.contains(StatisticsViewModel.alertDroppedErrorID) }
        XCTAssertEqual(
            dropLines, [
                StatisticsViewController.droppedAlertLine(
                    reason: StatisticsViewController.pendingAlertReason, message: "second"
                )
            ],
            "the second error is never shown, so it must leave exactly one line naming it; the sink saw \(lines)"
        )
        XCTAssertNil(controller.presentedViewController, "nothing may be presented from an off-window screen")
    }

    /// Read by its words: with the refusal reasons swapped or made identical,
    /// a test that only counted lines stays green.
    func testPresenterBeingDismissed_saysWhichTransition() {
        let host = StatsDismissingHost()
        attachToWindow(host)

        let dropLines = dropLinesFromShowing(on: host)

        XCTAssertTrue(host.wasAskedToPresent, "the reason is named after a refusal, not instead of asking")
        XCTAssertEqual(dropLines.count, 1, "a presenter mid-dismissal must leave one line")
        XCTAssertTrue(
            dropLines.first?.contains("StatsDismissingHost is being dismissed") == true,
            "the line must name the transition; it reads «\(dropLines.first ?? "")»"
        )
    }

    func testPresenterStillBeingPresented_saysWhichTransition() {
        let host = StatsPresentingHost()
        attachToWindow(host)

        let dropLines = dropLinesFromShowing(on: host)

        XCTAssertTrue(host.wasAskedToPresent, "the reason is named after a refusal, not instead of asking")
        XCTAssertEqual(dropLines.count, 1, "a presenter mid-presentation must leave one line")
        XCTAssertTrue(
            dropLines.first?.contains("StatsPresentingHost is itself still being presented") == true,
            "the line must name the transition; it reads «\(dropLines.first ?? "")»"
        )
    }

    /// The refusal nothing can name: `present` returns and the alert is not
    /// up, with the presenter in a window and in no transition.
    func testPresenterSwallowsTheCall_readBackStillLeavesALine() {
        let host = StatsSwallowingHost()
        attachToWindow(host)
        XCTAssertNil(
            StatisticsViewController.droppedAlertDiagnostic(presenter: host, message: "any"),
            "test precondition: the guard must PASS, so a line can only come from the read-back"
        )

        let dropLines = dropLinesFromShowing(on: host)

        XCTAssertTrue(host.wasAskedToPresent, "test precondition: the call has to have reached `present`")
        XCTAssertEqual(dropLines.count, 1, "a refusal the guard cannot name must still leave one line")
        XCTAssertTrue(
            dropLines.first?.contains("StatsSwallowingHost did not put the alert up") == true,
            "the line must name who refused; it reads «\(dropLines.first ?? "")»"
        )
    }

    // MARK: - Helpers

    /// Synchronous: every refusal path returns inside the call, so the sink
    /// needs no run loop.
    private func dropLinesFromShowing(on host: UIViewController) -> [String] {
        var lines: [String] = []
        AppLogger.withTestSink({ lines.append($2) }, perform: {
            StatisticsViewController.showLoadErrorAlert(on: host, message: "unshown")
        })
        XCTAssertTrue(
            lines.allSatisfy { !$0.contains(StatisticsViewModel.alertShownErrorID) },
            "nothing reached the screen, so nothing may claim it did; the sink saw \(lines)"
        )
        return lines.filter { $0.contains(StatisticsViewModel.alertDroppedErrorID) && $0.contains("unshown") }
    }

    private func attachToWindow(_ host: UIViewController) {
        window.addSubview(host.view)
        XCTAssertNotNil(
            host.viewIfLoaded?.window,
            "test precondition: the presenter must be IN a window, or the window check answers first"
        )
    }
}

// MARK: - Errors that arrive before the view is in the window (#825)

/// An extension only to keep the class body under SwiftLint's
/// `type_body_length`; XCTest finds test methods here the same way.
extension StatisticsLoadErrorAlertTests {

    /// The production order, with the error coming from the real load: an
    /// injected view model on a corrupt ledger this test owns, so
    /// `loadData()` fails inside the real `viewWillAppear`.
    ///
    /// ⚠️ The appearance is driven by hand, through UIKit's container
    /// contract (`beginAppearanceTransition` before the child's view is in the
    /// window, `endAppearanceTransition` after). Round 1 of #825 switched
    /// `UITabBarController.selectedIndex` in this suite's scene-less window
    /// instead. The tab bar never put the child's view in the window, and
    /// `viewDidAppear` never ran (CI 35862589456, 6 failures). A container that
    /// does not forward appearance on its own makes both callbacks happen
    /// exactly when this test says.
    ///
    /// Waits for ALERT-SHOWN inside the sink, and drains the main queue right
    /// before it: a SHOWN line from a completion that ran after the sink was
    /// removed would land in whichever test ran next (#742 §2a).
    func testErrorFromARealViewWillAppear_isShownFromViewDidAppearOnce() {
        let mounted = showHeldErrorThroughARealAppearance()

        let alert = (mounted.host.presentedViewController ?? mounted.stats.presentedViewController)
            as? UIAlertController
        XCTAssertNotNil(
            alert,
            """
            the held error must come up once the view is in the window. \
            \(presentationDiagnostics(rootedAt: mounted.host))
            """
        )
        XCTAssertEqual(
            alert?.message, Localized.text("wallet.error.load_failed"),
            "the alert must carry the held message"
        )
        XCTAssertNil(mounted.stats.pendingLoadErrorMessage, "a shown error must not stay held")
        XCTAssertEqual(
            mounted.lines.filter { $0.contains(StatisticsViewModel.alertShownErrorID) }.count, 1,
            "one alert on screen, one SHOWN line; the sink saw \(mounted.lines)"
        )
        XCTAssertEqual(
            mounted.lines.filter { $0.contains(StatisticsViewModel.alertDroppedErrorID) }.count, 0,
            "an alert on screen must not also be reported as dropped; the sink saw \(mounted.lines)"
        )
    }

    /// A shown error is not shown, or dropped, a second time. After the alert
    /// is dismissed and the ledger repaired, the screen disappears and appears
    /// again. That produces no SHOWN, no DROPPED and no presentation.
    ///
    /// This covers the mutant that keeps the message after showing it. A
    /// kept message would be caught by the next `viewWillAppear` and logged as
    /// superseded, so the DROPPED count is what goes red.
    func testShownError_isNotRepeatedOnTheNextAppearance() {
        let mounted = showHeldErrorThroughARealAppearance()
        XCTAssertNotNil(mounted.host.presentedViewController, "test precondition: the first alert must be up")

        mounted.ledger.removeObject(forKey: "stored_transactions")
        mounted.host.dismiss(animated: false)
        let dismissed = expectation(description: "the first alert went away")
        let deadline = Date().addingTimeInterval(20)
        func poll() {
            if mounted.host.presentedViewController == nil || Date() >= deadline {
                dismissed.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
        }
        poll()
        wait(for: [dismissed], timeout: 25)
        XCTAssertNil(mounted.host.presentedViewController, "test precondition: the first alert must be gone")

        var lines: [String] = []
        drainMainQueue()
        AppLogger.withTestSink({ lines.append($2) }, perform: {
            mounted.stats.beginAppearanceTransition(false, animated: false)
            mounted.stats.endAppearanceTransition()
            mounted.stats.beginAppearanceTransition(true, animated: false)
            mounted.stats.endAppearanceTransition()
        })

        XCTAssertNil(mounted.host.presentedViewController, "nothing is wrong any more, so nothing may come up")
        XCTAssertNil(
            mounted.stats.viewModel.ledgerUnavailableReason,
            "test precondition: the reload must have succeeded"
        )
        XCTAssertTrue(
            lines.allSatisfy {
                !$0.contains(StatisticsViewModel.alertShownErrorID)
                    && !$0.contains(StatisticsViewModel.alertDroppedErrorID)
            },
            "an error already shown must leave no second line; the sink saw \(lines)"
        )
    }

    /// The case the review found: an error is held, `viewDidAppear` never
    /// comes (a cancelled back-swipe), and the next appearance reloads a
    /// HEALTHY ledger. The old message would describe data that is now on
    /// screen, so it is thrown away with a line and nothing is presented.
    func testHeldErrorThenAHealthyReload_dropsTheStaleMessageAndShowsNothing() {
        let (stats, _) = makeStatsOnOwnLedger(corrupt: false)
        stats.loadViewIfNeeded()

        var lines: [String] = []
        AppLogger.withTestSink({ lines.append($2) }, perform: {
            stats.viewModel.onLoadError?(StatsStubLoadError(errorDescription: "stale"))
            stats.beginAppearanceTransition(true, animated: false)
            stats.endAppearanceTransition()
        })

        XCTAssertNil(stats.pendingLoadErrorMessage, "the reload replaced the held message")
        XCTAssertNil(stats.viewModel.ledgerUnavailableReason, "test precondition: the reload must have succeeded")
        XCTAssertNil(stats.presentedViewController, "nothing may be presented about data that loaded")
        XCTAssertEqual(
            lines.filter { $0.contains(StatisticsViewModel.alertDroppedErrorID) },
            [
                StatisticsViewController.droppedAlertLine(
                    reason: StatisticsViewController.supersededAlertReason, message: "stale"
                )
            ],
            "the stale message was never shown, so it must leave exactly one line; the sink saw \(lines)"
        )
        XCTAssertTrue(
            lines.allSatisfy { !$0.contains(StatisticsViewModel.alertShownErrorID) },
            "nothing reached the screen; the sink saw \(lines)"
        )
    }

    /// The same cancelled appearance, but the ledger is STILL broken on the
    /// next one. Pins the order in `viewWillAppear`: the held message is
    /// superseded before the reload, so the reload's fresh error is the one
    /// held. Superseding after the load would drop the fresh error as
    /// "already waiting" and then throw away the stale one, and this
    /// appearance would show nothing about a ledger that is still unreadable.
    func testHeldErrorThenAStillBrokenReload_replacesTheHeldMessage() {
        let (stats, _) = makeStatsOnOwnLedger(corrupt: true)
        stats.loadViewIfNeeded()

        var lines: [String] = []
        AppLogger.withTestSink({ lines.append($2) }, perform: {
            stats.viewModel.onLoadError?(StatsStubLoadError(errorDescription: "stale"))
            stats.beginAppearanceTransition(true, animated: false)
        })

        XCTAssertEqual(
            stats.pendingLoadErrorMessage, Localized.text("wallet.error.load_failed"),
            "the reload's own error must be the one held for this appearance"
        )
        XCTAssertEqual(
            lines.filter { $0.contains(StatisticsViewModel.alertDroppedErrorID) },
            [
                StatisticsViewController.droppedAlertLine(
                    reason: StatisticsViewController.supersededAlertReason, message: "stale"
                )
            ],
            "only the stale message may be dropped; the sink saw \(lines)"
        )
        // Balances the transition. Off-window, so `viewDidAppear` keeps the
        // fresh message held and logs nothing.
        stats.endAppearanceTransition()
    }

    /// A held message whose screen is released before it appears still leaves
    /// its DROPPED line, from the isolated `deinit`.
    func testHeldErrorOfAReleasedScreen_leavesADroppedLine() {
        var lines: [String] = []
        weak var released: StatisticsViewController?
        AppLogger.withTestSink({ lines.append($2) }, perform: {
            autoreleasepool {
                let (stats, _) = makeStatsOnOwnLedger(corrupt: false)
                stats.loadViewIfNeeded()
                stats.viewModel.onLoadError?(StatsStubLoadError(errorDescription: "never seen"))
                released = stats
            }
        })

        XCTAssertNil(released, "test precondition: the screen must be released, or `deinit` never ran")
        XCTAssertEqual(
            lines.filter { $0.contains(StatisticsViewModel.alertDroppedErrorID) },
            [
                StatisticsViewController.droppedAlertLine(
                    reason: StatisticsViewController.releasedAlertReason, message: "never seen"
                )
            ],
            "a held message that dies with its screen must leave one line; the sink saw \(lines)"
        )
    }

    /// A screen whose view model reads a ledger this test owns, not
    /// `UserDefaults.standard`. With `corrupt`, the load inside a real
    /// `viewWillAppear` fails the same way `corruptTheLedger()` makes it fail
    /// in `StatisticsLoadFailureTraceTests` (#825).
    private func makeStatsOnOwnLedger(corrupt: Bool) -> (StatisticsViewController, UserDefaults) {
        let name = "test.statsAlertLedger.\(UUID().uuidString)"
        ledgerSuiteNames.append(name)
        let ledger = UserDefaults(suiteName: name)!
        if corrupt {
            ledger.set(Data("not json".utf8), forKey: "stored_transactions")
        }
        let wakeStore = WakeEventStore(defaults: ledger)
        let viewModel = StatisticsViewModel(
            repository: TransactionRepository(defaults: ledger, wakeStore: wakeStore),
            wakeStore: wakeStore,
            defaults: ledger
        )
        return (StatisticsViewController(viewModel: viewModel), ledger)
    }

    /// Runs the production order on a corrupt ledger and waits for SHOWN
    /// inside the sink:
    ///   1. `viewWillAppear` while the view is not in the window. The real
    ///      load fails and the error is held: nothing presented, no line.
    ///   2. The view goes into the window, then `viewDidAppear`.
    ///
    /// Step 1 is asserted here, so every caller checks it. An empty
    /// `presentedViewController` is consistent with `present` not having been
    /// called, but it does not prove it for this container. UIKit's
    /// through-the-ancestor presentation was characterised for a tab bar,
    /// not for this host. The direct pin is `testLoadErrorOffWindow_…`: its
    /// screen has no parent, so a `present` there would be refused and the
    /// read-back would write a DROPPED line.
    private func showHeldErrorThroughARealAppearance() -> StatsMountedAppearance {
        let (stats, ledger) = makeStatsOnOwnLedger(corrupt: true)
        let host = StatsManualAppearanceHost()
        window.rootViewController = host
        window.makeKeyAndVisible()
        XCTAssertNotNil(host.viewIfLoaded?.window, "test precondition: the container must be on screen")
        host.addChild(stats)
        stats.loadViewIfNeeded()

        let shown = expectation(description: "the ALERT-SHOWN line reached the seam")
        var lines: [String] = []
        var fulfilled = false
        drainMainQueue()
        AppLogger.withTestSink({ _, _, line in
            lines.append(line)
            if !fulfilled, line.contains(StatisticsViewModel.alertShownErrorID) {
                fulfilled = true
                shown.fulfill()
            }
        }, perform: {
            stats.beginAppearanceTransition(true, animated: false)
            XCTAssertNil(stats.viewIfLoaded?.window, "test precondition: viewWillAppear must run off-window")
            XCTAssertEqual(
                stats.pendingLoadErrorMessage, Localized.text("wallet.error.load_failed"),
                "the real load must have failed and its error been held; the sink saw \(lines)"
            )
            XCTAssertNil(host.presentedViewController, "nothing may be presented while the view is off-window")
            XCTAssertTrue(
                lines.allSatisfy {
                    !$0.contains(StatisticsViewModel.alertShownErrorID)
                        && !$0.contains(StatisticsViewModel.alertDroppedErrorID)
                },
                "a held error is neither shown nor dropped yet; the sink saw \(lines)"
            )

            stats.view.frame = host.view.bounds
            host.view.addSubview(stats.view)
            stats.didMove(toParent: host)
            XCTAssertNotNil(stats.viewIfLoaded?.window, "test precondition: viewDidAppear must run in the window")
            stats.endAppearanceTransition()
            wait(for: [shown], timeout: 25)
        })
        return StatsMountedAppearance(host: host, stats: stats, ledger: ledger, lines: lines)
    }
}
