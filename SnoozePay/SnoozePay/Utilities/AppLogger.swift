import Foundation
import os

/// Unified `os.Logger` access for production code.
///
/// Replaces ad-hoc `print("[Subsystem] ...")` statements scattered across
/// services, view-models and the AppDelegate. Each category surfaces in
/// Console.app and Xcode's debug console with a consistent subsystem so
/// support sessions / TestFlight crash investigations can be filtered by
/// `subsystem == "app.snoozepay"` and drilled down by category.
///
/// Use the level that matches the event:
/// - `.debug` — verbose diagnostic only useful while reproducing a bug.
/// - `.info` — routine lifecycle events (purchase succeeded, snooze scheduled).
/// - `.notice` — noteworthy but non-error transitions (fallback paths taken).
/// - `.warning` — recoverable malfunctions the user might notice.
/// - `.error` — failures that prevent the requested operation.
///
/// Sensitive identifiers (alarm UUIDs, StoreKit transaction IDs) MUST use
/// `privacy: .private` interpolation so they are redacted in shipping logs.
enum AppLogger {

    /// Subsystem string used by every logger. Matches the bundle's
    /// reverse-DNS prefix so Console.app filters work identically against
    /// debug builds and TestFlight archives.
    private static let subsystem = "app.snoozepay"

    /// Alarm scheduling, list / firing view-model state transitions.
    static let alarms = Logger(subsystem: subsystem, category: "alarms")

    /// StoreKit purchase / restore / verification flows.
    static let storeKit = Logger(subsystem: subsystem, category: "storekit")

    /// UNUserNotificationCenter delegate events and permission state.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// AVAudioSession configuration and AVAudioPlayer playback state.
    static let audio = Logger(subsystem: subsystem, category: "audio")

    /// Persistence layer (UserDefaults-backed repositories) — reserved for
    /// future use; centralising the category here so callers don't invent
    /// ad-hoc strings.
    static let repository = Logger(subsystem: subsystem, category: "repository")
}
