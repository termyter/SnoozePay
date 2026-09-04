import Foundation
import os

/// Category-scoped `os.Logger` instances for production logging.
///
/// Replaces ad-hoc `print("[Tag] msg")` statements scattered across services
/// and view models so logs:
///   * land in unified Apple logging (Console.app, Xcode Organizer, sysdiagnose)
///     with severity, subsystem, and category — searchable instead of grep'ing
///     stdout;
///   * honour `os_log` privacy markers so identifiers (alarm UUIDs,
///     transaction IDs) don't leak into shared diagnostics by default;
///   * avoid the main-thread cost of `print()` on hot paths.
///
/// The subsystem IS the running app's bundle identifier, read from
/// `Bundle.main`, so logs filter cleanly to this app in tools that aggregate
/// across processes — and the string to filter by is one the reader already
/// has, instead of one they have to know about in advance.
///
/// Usage:
///   AppLogger.scheduler.error("schedule failed: \(error.localizedDescription, privacy: .public)")
///   AppLogger.audio.notice("startAlarmSound: vibration only — no audio source")
enum AppLogger {

    /// The `os_log` subsystem every line of this app ships under: the bundle
    /// identifier of the process that is running, resolved once at first use.
    ///
    /// Resolved rather than spelled out because a spelled-out one drifts. This
    /// one did: it stayed `Ivan-Emelyanov.SnoozePay` after the app moved to
    /// `io.mobilife.SnoozePay` (#475/#476), so a support grep written from the
    /// docstring above it matched nothing at all (#670).
    ///
    /// It was `fileprivate`, which already served ``AppLogCategory`` — that
    /// lives in this file. Internal is for the two readers outside it: the
    /// older `OSLog(subsystem:category:)` sites in `Services/` and ``Money``,
    /// and `AppLoggerSubsystemTests`.
    static let subsystem: String = {
        guard let identifier = Bundle.main.bundleIdentifier else {
            // Unreachable in all three targets this project has — see
            // ``fallbackSubsystem``. The trap is what keeps that a checked
            // claim rather than a remembered one, and it costs nothing while
            // the claim holds. Were it ever to fire in release, the lines
            // would carry the app's subsystem from a process that is not the
            // app: a support grep would find them and believe them.
            assertionFailure(
                "Bundle.main declares no CFBundleIdentifier; logs would be misattributed to the app"
            )
            return AppLogger.fallbackSubsystem
        }
        return identifier
    }()

    /// What ``subsystem`` falls back to when `Bundle.main` declares no
    /// `CFBundleIdentifier`.
    ///
    /// `bundleIdentifier` is `String?`, so the arm has to exist. It is not
    /// reachable from any target this project has, and saying where the value
    /// comes from is the point: `Info.plist` in the repository declares no
    /// `CFBundleIdentifier` at all — the build injects it from
    /// `PRODUCT_BUNDLE_IDENTIFIER` under `GENERATE_INFOPLIST_FILE = YES`, and
    /// that setting is a no-touch zone. This target's unit tests run inside the
    /// app process via `TEST_HOST`, and the UI-test runner never links this
    /// module, so neither reaches here either. What would is a bundle-less host
    /// this project does not build: a command-line tool linking the module.
    /// (Not `xctest` — that tool carries `com.apple.dt.xctest.tool` of its own.)
    ///
    /// Being a literal, this is the one line in the file that can go stale the
    /// same way #670 did.
    /// `AppLoggerSubsystemTests.testTheFallbackLiteralStillSpellsTheAppsBundleIdentifier`
    /// makes the next bundle-identifier change red instead of silent.
    static let fallbackSubsystem = "io.mobilife.SnoozePay"

    // The eight `static let`s below DERIVE from ``AppLogCategory`` rather than
    // repeating `Logger(subsystem:category:)`, so a category name is spelled in
    // exactly one place.
    //
    // ⚠️ That removes the typo, not the mismatch. `static let repository =
    // AppLogCategory.ui.logger` compiles, ships every repository line under
    // «UI», and leaves the whole target green — `os.Logger` is not `Equatable`
    // and does not hand back its category, so nothing can assert this pairing.
    // It is a read-with-your-eyes invariant, held only by the case name sitting
    // on the same line as the property name. Review caught an earlier revision
    // of this comment claiming the two «cannot drift apart».

    /// AlarmScheduler — permission flow, schedule failures, snooze rescheduling.
    static let scheduler = AppLogCategory.scheduler.logger

    /// AudioService — audio session config, AVAudioPlayer init/play, fallback paths.
    static let audio = AppLogCategory.audio.logger

    /// BalanceService — charge / topUp diagnostics (currently unused; reserved).
    static let balance = AppLogCategory.balance.logger

    /// AlarmRepository / TransactionRepository — persistence read/write failures.
    static let repository = AppLogCategory.repository.logger

    /// StoreKitService — purchase, restore, verification, idempotency dedup.
    static let storeKit = AppLogCategory.storeKit.logger

    /// AlarmFiringCoordinator — snooze action routing from notification taps.
    static let coordinator = AppLogCategory.coordinator.logger

    /// AppDelegate — launch wiring, notification permission, willPresent / didReceive.
    static let appDelegate = AppLogCategory.appDelegate.logger

    /// ViewModels / ViewControllers — UI-side diagnostics that don't fit a service.
    static let ui = AppLogCategory.ui.logger
}

// MARK: - The observable seam (#731)

/// A category on ``AppLogger``, named so a line routed through
/// ``AppLogger/emit(_:_:_:)`` can be read back by a test without the test
/// knowing which `Logger` it landed on.
///
/// `Logger` itself cannot serve here: it is a value that writes into unified
/// logging and hands the caller nothing back. That is fine for the direct call
/// sites, and it is the whole problem for a DEFAULT — a closure whose body only
/// writes to `os.Logger` is unreachable for a mutation check, so emptying it
/// leaves every test green. #716 closed the same hole one level down, where the
/// default was `XCTFail` and therefore observable from inside XCTest.
///
/// The raw value IS the `os_log` category, and the loggers are built from it.
/// An earlier revision mapped case to logger with a `switch`, which review
/// caught as unobservable by construction: with a test sink installed `emit`
/// returns before `logger` is ever evaluated, so swapping two arms left the
/// whole 1034-test target green. A mapping nothing can assert is the defect
/// this seam exists to close, one level up. As data, the case-to-logger step is
/// correct by construction and needs no test at all.
///
/// What still needs one is the raw values themselves: they ARE the `os_log`
/// categories a support ticket is grepped by, and renaming one retargets every
/// such grep without failing anything. `testEveryCategoryKeepsItsOsLogName`
/// pins them. Uniqueness is NOT that test's job — the compiler rejects a
/// duplicate raw value outright.
enum AppLogCategory: String, CaseIterable {
    case scheduler = "Scheduler"
    case audio = "Audio"
    case balance = "Balance"
    case repository = "Repo"
    case storeKit = "StoreKit"
    case coordinator = "Coordinator"
    case appDelegate = "AppDelegate"
    case ui = "UI"

    /// Built once per case, not per line: `Logger(subsystem:category:)` creates
    /// an `os_log_t`, and this seam is meant to take call sites at every level,
    /// including `.debug` ones that fire often.
    ///
    /// The `??` arm is unreachable: the table is built from `allCases`, and a
    /// case added later joins `allCases` on its own, so there is no way to add
    /// one without an entry. It is spelled out rather than force-unwrapped
    /// because a crash in the logging seam is a worse trade than a duplicate
    /// `os_log_t` in a branch that cannot be taken.
    var logger: Logger {
        Self.loggers[self] ?? Logger(subsystem: AppLogger.subsystem, category: rawValue)
    }

    private static let loggers: [AppLogCategory: Logger] = Dictionary(
        uniqueKeysWithValues: allCases.map {
            ($0, Logger(subsystem: AppLogger.subsystem, category: $0.rawValue))
        }
    )
}

extension AppLogger {

    /// Where a log line goes when it is written from somewhere a test has to be
    /// able to see — a default closure, or a branch whose only evidence is the
    /// line itself.
    typealias Sink = (AppLogCategory, OSLogType, String) -> Void

    #if DEBUG
    /// Test-only redirect for ``emit(_:_:_:)``.
    ///
    /// `private(set)`, so the only way to install one is
    /// ``withTestSink(_:perform:)``. A direct assignment with no matching
    /// restore would absorb every later suite's lines while those suites assert
    /// on absence — green while observing nothing, which is the same defect one
    /// level up. Review asked for this: the doc used to merely ASK callers to
    /// go through the helper, and a rule nobody enforces is a rule that holds
    /// only while someone is reading it.
    private(set) static var testSink: Sink?

    /// Runs `perform` with `sink` installed, then puts back whatever was there.
    ///
    /// `defer`, not a `tearDown`: a test that throws or returns early still
    /// restores.
    ///
    /// ⚠️ Nesting SHADOWS rather than chains: while an inner sink is installed
    /// the outer one sees nothing, and gets the lines back only after the inner
    /// scope ends. That follows from there being ONE global, the same way
    /// case-to-logger follows from the table — no test asserts it, and
    /// `testWithTestSink_restoresThePreviousSink_evenWhenTheBodyThrows` pins
    /// only the restoring half (its inner body emits nothing, so a chaining
    /// implementation would pass it too). The consequence is worth knowing
    /// anyway: a helper that quietly opens its own window inside someone
    /// else's would make the outer `count ==` short by exactly the lines it
    /// swallowed, with nothing red to say so.
    ///
    /// ⚠️ `perform` is SYNCHRONOUS and non-escaping, so the sink is gone the
    /// instant it returns. A line emitted from a completion handler — a
    /// `present(_:animated:completion:)` completion, an `async` continuation —
    /// fires on a later runloop turn, so wrapping the *call* alone never sees
    /// it: by the time the handler runs, the sink is already restored.
    ///
    /// That is a matter of COST, not of possibility, and an earlier revision
    /// of this comment overstated it as the latter. `perform` is synchronous,
    /// but its BODY may turn the run loop — a `wait(for:timeout:)` inside it
    /// keeps the sink installed for the whole wait.
    ///
    /// `StatisticsViewController`'s ALERT-SHOWN line is exactly that shape and
    /// is covered that way by
    /// `StatisticsLoadErrorAlertTests.testFirstLoadError_logsThatTheUserActuallySawIt`
    /// (#742). Copy its shape rather than its ingredients: it waits for the
    /// LINE, not for `presentedViewController`, which UIKit sets inside
    /// `present` — before the completion runs — so a wait on that property
    /// samples the sink too early and passes or fails on timing.
    static func withTestSink<T>(_ sink: @escaping Sink, perform: () throws -> T) rethrows -> T {
        let previous = testSink
        testSink = sink
        defer { testSink = previous }
        return try perform()
    }
    #endif

    /// Writes one line to `category`'s logger — or to the installed test sink.
    ///
    /// The message is interpolated `privacy: .public`, which is what every call
    /// site moved onto this seam already did explicitly, so the TEXT that
    /// reaches unified logging is unchanged. Its shape is not: `Logger.error`
    /// stores a format string plus its arguments as separate fields, `emit`
    /// stores one already-built `%{public}s`. Nothing the app or a support grep
    /// reads depends on that, but a Console predicate written against an
    /// argument field would. Pass only text that is safe to make
    /// public: this seam makes `.public` the frictionless choice, and the file
    /// header's posture — identifiers do not leak by default — has to be kept
    /// by the caller here. An identifier still belongs at a direct
    /// `AppLogger.<category>` call with its own `privacy:` marker.
    ///
    /// `level` is `OSLogType`, which has no `.notice` — `Logger.notice(_:)` is
    /// spelled `.default` here, and that is the same level, not a downgrade.
    ///
    /// ⚠️ Two properties a caller has to know before moving a line here:
    ///
    /// - **Main thread only.** `testSink` is an unguarded mutable global. Every
    ///   call site today is main-thread; the first `emit` from a StoreKit
    ///   `async` context or a notification callback would race the install, and
    ///   under `SWIFT_VERSION = 5.0` nothing warns. Serialise it before taking
    ///   this seam off the main thread.
    /// - **The message is built eagerly.** `Logger.error(_:)` autoclosures its
    ///   interpolation and only materialises it when the level is enabled;
    ///   `emit` takes a `String` that is already built. Harmless at `.error`,
    ///   which is always enabled, and a real cost for a `.debug` line on a hot
    ///   path — those should stay on the direct call.
    ///
    /// One thing this seam does NOT make observable is its own last line. With
    /// a sink installed `emit` returns above it, so no test reaches the
    /// `category.logger.log` call: delete it and every line routed through the
    /// seam vanishes from release builds while the suite stays green. That is
    /// still the better trade — one unobservable line instead of one per call
    /// site — but it is the residue, not zero, and reading it back would mean
    /// polling `OSLogStore`, which is what this PR set out to avoid.
    static func emit(_ category: AppLogCategory, _ level: OSLogType, _ message: String) {
        #if DEBUG
        if let testSink {
            testSink(category, level, message)
            return
        }
        #endif
        category.logger.log(level: level, "\(message, privacy: .public)")
    }
}
