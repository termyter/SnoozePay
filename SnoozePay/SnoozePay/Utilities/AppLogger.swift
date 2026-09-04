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

    private static let subsystem = "Ivan-Emelyanov.SnoozePay"

    /// AlarmScheduler — permission flow, schedule failures, snooze rescheduling.
    static let scheduler = Logger(subsystem: subsystem, category: "Scheduler")

    /// AudioService — audio session config, AVAudioPlayer init/play, fallback paths.
    static let audio = Logger(subsystem: subsystem, category: "Audio")

    /// BalanceService — charge / topUp diagnostics (currently unused; reserved).
    static let balance = Logger(subsystem: subsystem, category: "Balance")

    /// AlarmRepository / TransactionRepository — persistence read/write failures.
    static let repository = Logger(subsystem: subsystem, category: "Repo")

    /// StoreKitService — purchase, restore, verification, idempotency dedup.
    static let storeKit = Logger(subsystem: subsystem, category: "StoreKit")

    /// AlarmFiringCoordinator — snooze action routing from notification taps.
    static let coordinator = Logger(subsystem: subsystem, category: "Coordinator")

    /// AppDelegate — launch wiring, notification permission, willPresent / didReceive.
    static let appDelegate = Logger(subsystem: subsystem, category: "AppDelegate")

    /// ViewModels / ViewControllers — UI-side diagnostics that don't fit a service.
    static let ui = Logger(subsystem: subsystem, category: "UI")
}

// MARK: - The observable seam (#731)

/// A category on ``AppLogger``, named so a line routed through ``AppLogger/emit(_:_:_:)``
/// can be read back by a test without the test knowing which `Logger` it landed on.
///
/// `Logger` itself cannot serve here: it is a value that writes into unified
/// logging and hands the caller nothing back. That is fine for the 145 direct
/// call sites, and it is the whole problem for a DEFAULT — a closure whose body
/// only writes to `os.Logger` is unreachable for a mutation check, so emptying
/// it leaves every test green. #716 closed the same hole one level down, where
/// the default was `XCTFail` and therefore observable from inside XCTest.
enum AppLogCategory: CaseIterable {
    case scheduler, audio, balance, repository, storeKit, coordinator, appDelegate, ui

    var logger: Logger {
        switch self {
        case .scheduler: return AppLogger.scheduler
        case .audio: return AppLogger.audio
        case .balance: return AppLogger.balance
        case .repository: return AppLogger.repository
        case .storeKit: return AppLogger.storeKit
        case .coordinator: return AppLogger.coordinator
        case .appDelegate: return AppLogger.appDelegate
        case .ui: return AppLogger.ui
        }
    }
}

extension AppLogger {

    /// Where a log line goes when it is written from somewhere a test has to be
    /// able to see — a default closure, or a branch whose only evidence is the
    /// line itself.
    typealias Sink = (AppLogCategory, OSLogType, String) -> Void

    #if DEBUG
    /// Test-only redirect for ``emit(_:_:_:)``. Install it with
    /// ``withTestSink(_:perform:)`` rather than assigning directly, so a suite
    /// cannot leave one behind and silently swallow another suite's lines.
    ///
    /// Shaped after `AlarmBackendAvailability.uiTourForcedAvailability`: a
    /// DEBUG-only override consulted before the production path, so the release
    /// binary does not even contain the branch.
    static var testSink: Sink?

    /// Runs `perform` with `sink` installed, then puts back whatever was there.
    ///
    /// `defer`, not a `tearDown`: a test that throws or returns early still
    /// restores. A leaked sink is worse than no seam at all — it would absorb
    /// the lines of every suite that runs after it, and those suites assert on
    /// *absence* in places, so they would stay green while observing nothing.
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
    /// public; identifiers still need their own `privacy:` marker at a direct
    /// `AppLogger.<category>` call.
    ///
    /// `level` is `OSLogType`, which has no `.notice` — `Logger.notice(_:)` is
    /// spelled `.default` here, and that is the same level, not a downgrade.
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
