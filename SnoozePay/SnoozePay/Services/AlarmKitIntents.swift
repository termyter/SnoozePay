import Foundation
import os
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - AlarmKit alert button intents (#377)
//
// AlarmKit (iOS 26+, Strategy A) does NOT use UNNotificationAction-style action
// identifiers routed through the UNUserNotificationCenter delegate. Instead the
// system-rendered full-screen alert's buttons are wired to `LiveActivityIntent`
// instances handed to `AlarmManager` at schedule time
// (`AlarmConfiguration.stopIntent` / `.secondaryIntent`). When the user taps a
// button on the lock-screen / Dynamic-Island alarm presentation, the system
// runs the corresponding intent's `perform()` in our app process — even while
// the device is locked.
//
// These two intents are the AlarmKit analogue of the
// `DISMISS_ACTION` / `SNOOZE_ACTION` notification actions handled in
// `AppDelegate.userNotificationCenter(_:didReceive:)`:
//   * `StopAlarmIntent`   → stop ringing, record the wake day (no charge).
//   * `SnoozeAlarmIntent`  → charge the (progressive) penalty, reschedule via
//                            `AlarmFiringCoordinator`, re-arm the snooze alarm.
//
// Both carry the alarm UUID as a plain string parameter so the system can
// persist + replay them, and both resolve the alarm from `AlarmRepository`
// rather than trusting any payload state — the repository is the single source
// of truth for penalty / snooze settings (mirrors the notification path).

#if canImport(AppIntents)

@available(iOS 26.0, *)
struct StopAlarmIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "Выключить будильник"

    /// UUID string of the alarm whose AlarmKit alert this button belongs to.
    /// Stored as a string because `IntentParameter` does not support `UUID`
    /// directly and the system serialises the intent for later replay.
    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await AlarmKitActionRouter.shared.handleStop(alarmIDString: alarmID)
        return .result()
    }
}

@available(iOS 26.0, *)
struct SnoozeAlarmIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "Поспать ещё"

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await AlarmKitActionRouter.shared.handleSnooze(alarmIDString: alarmID)
        return .result()
    }
}

#endif

/// Shared, framework-free router for AlarmKit alert-button actions. Extracted
/// from the intents so the business logic (charge + reschedule + wake-event)
/// is unit-testable without standing up AppIntents / AlarmKit — the intents
/// are thin shells whose only job is to forward to this type.
///
/// Always available (no `@available` gate) so the test target and the
/// `< iOS 26` build can reference it; the intents that call it are the
/// iOS-26-gated surface.
///
/// `@MainActor`-isolated: every action it performs touches a UI-adjacent
/// singleton (`AudioService`, `AlarmScheduler`, `WakeEventStore`,
/// `AlarmFiringCoordinator`), and the AppIntent `perform()` that drives it is
/// itself main-actor isolated — keeping the router on the main actor avoids
/// cross-actor hops and the Swift-6 isolation diagnostics they raise.
@MainActor
final class AlarmKitActionRouter {

    static let shared = AlarmKitActionRouter()

    private init() {}

    /// Stop the ringing alarm: silence audio + record the wake day. No charge —
    /// mirrors the `DISMISS_ACTION` branch in `AppDelegate.didReceive`.
    func handleStop(alarmIDString: String) {
        guard let alarmID = UUID(uuidString: alarmIDString) else {
            AppLogger.scheduler.error(
                "AlarmKit stop: malformed alarmID \(alarmIDString, privacy: .public)"
            )
            return
        }
        AppLogger.scheduler.notice("AlarmKit stop alarm=\(alarmID, privacy: .private)")
        AudioService.shared.stopAlarmSound()
        WakeEventStore.shared.recordWake()
        // Stop the AlarmKit alert itself so the system stops the alarm UI.
        AlarmScheduler.shared.stopSystemAlarm(alarmID)
    }

    /// Snooze the ringing alarm: charge the penalty + reschedule. Routed
    /// through the same `AlarmFiringCoordinator` the notification path uses so
    /// the paid-snooze / refund-on-failure semantics stay identical (#377).
    func handleSnooze(alarmIDString: String) async {
        guard let alarmID = UUID(uuidString: alarmIDString) else {
            AppLogger.scheduler.error(
                "AlarmKit snooze: malformed alarmID \(alarmIDString, privacy: .public)"
            )
            return
        }
        AppLogger.scheduler.notice("AlarmKit snooze alarm=\(alarmID, privacy: .private)")
        AudioService.shared.stopAlarmSound()
        AlarmScheduler.shared.stopSystemAlarm(alarmID)

        // Reuse the notification-path payload contract so the coordinator's
        // charge / progressive-penalty / refund logic is shared verbatim. The
        // coordinator re-reads the alarm from the repository, so a minimal
        // payload (id + current snoozeCount) is enough — but we still need the
        // alarm's penalty settings to build a complete payload, so resolve it.
        guard let alarm = AlarmRepository.shared.fetch(id: alarmID) else {
            AppLogger.scheduler.notice(
                "AlarmKit snooze: alarm \(alarmID, privacy: .private) not found — skipping"
            )
            return
        }
        // AlarmKit owns its own snooze counter via repeated alerts; we start at
        // the alarm's base penalty (snoozeCount 0 → coordinator increments to 1).
        let payload = AlarmNotificationPayload(alarm: alarm, snoozeCount: 0)
        await withCheckedContinuation { continuation in
            AlarmFiringCoordinator.shared.handleSnooze(userInfo: payload.asUserInfo()) { outcome in
                AppLogger.scheduler.info(
                    "AlarmKit snooze outcome=\(String(describing: outcome), privacy: .public)"
                )
                continuation.resume()
            }
        }
    }
}
