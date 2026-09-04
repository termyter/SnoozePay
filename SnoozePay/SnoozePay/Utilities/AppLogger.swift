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
/// Subsystem matches the bundle identifier so logs filter cleanly to this
/// app in tools that aggregate across processes.
///
/// Usage:
///   AppLogger.scheduler.error("schedule failed: \(error.localizedDescription, privacy: .public)")
///   AppLogger.audio.notice("startAlarmSound: vibration only — no audio source")
enum AppLogger {

    /// Kept `fileprivate` rather than `private` so ``AppLogCategory`` can build
    /// the loggers from it. The eight `static let`s below now DERIVE from the
    /// cases rather than repeating `Logger(subsystem:category:)` — one place
    /// where a category name is spelled, so `AppLogger.repository` and
    /// `AppLogCategory.repository` cannot drift apart.
    fileprivate static let subsystem = "Ivan-Emelyanov.SnoozePay"

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
/// this seam exists to close, one level up. As data, it is one line and the
/// only thing that can go wrong — two cases sharing a name — is assertable.
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
    /// The `??` arm is unreachable — the table is built from `allCases`, so
    /// every case has an entry — and is spelled out rather than force-unwrapped
    /// so a future case added without rebuilding the table degrades to a
    /// correct logger instead of a crash.
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
    /// ⚠️ `perform` is SYNCHRONOUS and non-escaping, so the sink is gone the
    /// instant it returns. A line emitted from a completion handler — a
    /// `present(_:animated:completion:)` completion, an `async` continuation —
    /// fires on a later runloop turn and this helper cannot see it. Wrapping
    /// the *call* is not enough; the sink has to stay installed across the
    /// wait, which means paying wall-clock. `StatisticsViewController`'s
    /// ALERT-SHOWN line is exactly that shape and is deliberately left
    /// unobserved (#742).
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
    /// site moved onto this seam already did explicitly, so nothing about what
    /// reaches unified logging changes. Pass only text that is safe to make
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
