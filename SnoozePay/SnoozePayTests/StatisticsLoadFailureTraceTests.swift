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

/// The VC half: the alert the user actually gets, and the second one they
/// don't.
///
/// The seam needs no injection — `StatisticsViewController.viewModel` and
/// `StatisticsViewModel.onLoadError` are both internal and `bindViewModel()`
/// runs in `viewDidLoad`, so `loadViewIfNeeded()` plus a call through the
/// closure drives the real presentation path. `viewWillAppear` is never
/// reached, so no production `loadData()` runs and the shared repositories
/// stay untouched.
@MainActor
final class StatisticsLoadErrorAlertTests: XCTestCase {

    /// Held for the test's lifetime — a released window takes the controller
    /// under assertion with it.
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        // This suite spins the main run loop to wait for a presentation, so it
        // would otherwise spend the backlog the ~1000 preceding synchronous
        // tests left queued inside its own wait (#618, #693).
        drainMainQueue()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    override func tearDown() {
        window?.rootViewController?.dismiss(animated: false)
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func makeMountedController() -> StatisticsViewController {
        let controller = StatisticsViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
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
        let deadline = Date().addingTimeInterval(4)
        func poll() {
            if controller.presentedViewController != nil || Date() >= deadline {
                presented.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
        }
        poll()
        wait(for: [presented], timeout: 5)
        return controller.presentedViewController as? UIAlertController
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

        controller.viewModel.onLoadError?(decodeFailure())

        XCTAssertTrue(
            controller.presentedViewController === firstAlert,
            "a second alert must not replace or stack on the first"
        )
        let diagnostic = StatisticsViewController.droppedAlertDiagnostic(
            presenting: firstAlert, message: "message the user never saw"
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
        XCTAssertTrue(
            diagnostic?.contains("message the user never saw") == true,
            "the unshown message is the part worth recovering; it reads «\(diagnostic ?? "")»"
        )
    }

    /// The other half of that guard: with nothing presented there is nothing
    /// to report, and the alert goes up. Without this the previous test would
    /// pass against a controller that logs on every error and never presents.
    func testNothingPresented_producesNoDropDiagnostic() {
        XCTAssertNil(
            StatisticsViewController.droppedAlertDiagnostic(presenting: nil, message: "any"),
            "a free screen must present the alert, not log about dropping it"
        )
    }
}
