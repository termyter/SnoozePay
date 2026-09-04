import os
import XCTest
@testable import SnoozePay

/// Cover for the log lines that only a *default* writes (#731).
///
/// `StatisticsLoadFailureTraceTests` asserts the trace by injecting its own
/// `logLoadFailure`. That pins the call and says nothing about the default:
/// empty the default's body and the whole suite stays green, because no test
/// there ever runs without injecting first.
///
/// #716 closed exactly this hole one level down, where the default was
/// `XCTFail` and therefore observable from inside XCTest — `record(_:)` hands
/// the `XCTIssue` over. `os.Logger` has no such channel: it writes into unified
/// logging and returns nothing to the caller.
/// `OSLogStore(scope: .currentProcessIdentifier)` can read those entries back,
/// but only once they are flushed, so a test built on it has to poll against a
/// deadline — added wall-clock in a target that already carries a timeout flake
/// (#728). That trade is why the seam lives in `AppLogger` instead: one
/// redirect for the whole app, consulted before the `Logger` call, asserted
/// synchronously.
final class AppLoggerSinkTests: XCTestCase {

    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var txRepo: TransactionRepository!
    private var wakeStore: WakeEventStore!

    override func setUp() {
        super.setUp()
        suiteName = "test.appLoggerSink.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        wakeStore = WakeEventStore(defaults: testDefaults)
        txRepo = TransactionRepository(defaults: testDefaults, wakeStore: wakeStore)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// A ledger blob that cannot decode — the same one-liner the sibling trace
    /// suite uses, deliberately duplicated rather than shared: a fixture two
    /// suites reach into is a fixture either one can change for the other.
    private func corruptTheLedger() {
        testDefaults.set(Data("not json".utf8), forKey: "stored_transactions")
    }

    private func makeVM() -> StatisticsViewModel {
        StatisticsViewModel(
            repository: txRepo,
            wakeStore: wakeStore,
            defaults: testDefaults,
            calendar: StatisticsViewModel.mondayFirstCalendar
        )
    }

    // MARK: - The default nobody could see

    /// **This is the mutation target.** Empty the body of
    /// `StatisticsViewModel.logLoadFailure`'s default and this test — and, per
    /// the run table on the PR, only this test — goes red.
    ///
    /// The view model is built and left ALONE: no `logLoadFailure` assigned, no
    /// `onLoadError` bound. That is the shape production has on the first load,
    /// before `bindViewModel()` runs, and it is the shape no existing test
    /// covers, because every one of them injects a collector first.
    func testTheDefaultLoadFailureLog_actuallyReachesTheLogger() {
        corruptTheLedger()
        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []

        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }) {
            makeVM().loadData()
        }

        XCTAssertEqual(
            lines.count, 1,
            "one failed read must leave exactly one line through the default; it left \(lines.count)"
        )
        guard let line = lines.first else { return }
        XCTAssertEqual(line.category, .repository, "a persistence failure belongs to the Repo category")
        XCTAssertEqual(line.level, .error, "a ledger that cannot decode is not a notice")
        XCTAssertTrue(
            line.message.contains(StatisticsViewModel.ledgerUnreadableErrorID),
            "the line must carry the grep handle a support ticket is followed by; it reads «\(line.message)»"
        )
    }

    // MARK: - The seam itself

    /// A leaked sink would absorb every later suite's lines while those suites
    /// assert on absence — they would stay green observing nothing, which is
    /// the same defect this file exists to close, one level up. `withTestSink`
    /// therefore restores on the way out, including when the body throws.
    func testWithTestSink_restoresThePreviousSink_evenWhenTheBodyThrows() throws {
        struct Boom: Error {}
        var outer: [String] = []

        try AppLogger.withTestSink({ outer.append($2) }) {
            XCTAssertThrowsError(
                try AppLogger.withTestSink({ _, _, _ in }) { throw Boom() }
            )
            AppLogger.emit(.ui, .default, "after the inner sink is gone")
        }

        XCTAssertEqual(
            outer, ["after the inner sink is gone"],
            "the inner sink outlived its scope and swallowed the outer sink's line"
        )
        XCTAssertNil(
            AppLogger.testSink,
            "a sink outlived this test and will swallow the next suite's lines"
        )
    }

    /// `emit` must hand the sink back what it was given, unchanged, for every
    /// category — otherwise a caller's category is decided by the seam rather
    /// than by the caller, and lines land where nobody greps for them.
    ///
    /// Asserted over `allCases` rather than one sample: the routing lives in a
    /// `switch` whose arms are copy-paste of each other, and the failure mode
    /// of a slip there is one case answering with a neighbour's logger — which
    /// reads exactly like a working seam until someone follows a support ticket.
    func testEmit_passesTheCallersCategoryAndLevelThrough() {
        var seen: [(AppLogCategory, OSLogType)] = []

        AppLogger.withTestSink({ category, level, _ in seen.append((category, level)) }) {
            for category in AppLogCategory.allCases {
                AppLogger.emit(category, .fault, "probe")
            }
        }

        XCTAssertEqual(seen.map(\.0), AppLogCategory.allCases, "the seam reordered or dropped a category")
        XCTAssertTrue(seen.allSatisfy { $0.1 == .fault }, "the seam rewrote the caller's level")
    }
}
