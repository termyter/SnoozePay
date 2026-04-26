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
