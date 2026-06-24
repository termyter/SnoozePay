import Foundation
import os
#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
#endif

// MARK: - Strategy A: AlarmKit (#377)
//
// `docs/SPEC.md` §3.2.1 defines Strategy A — a real system-level alarm via the
// AlarmKit framework (iOS 26+). Unlike a `UNUserNotificationCenter` notification
// (Strategy B, the fallback), an AlarmKit alarm rings continuously, pierces
// silent mode and Focus/DND, and shows a full-screen alert on the lock screen —
// exactly like Clock.app — WITHOUT the Critical Alerts entitlement (which is
// not approved on the Personal team).
//
// This file owns the AlarmKit wrapper. `AlarmScheduler` (Strategy B) decides at
// runtime which backend to use: AlarmKit on iOS 26+, the existing notification
// scheduler below it.

/// Backend-agnostic seam over the AlarmKit `AlarmManager`. Extracted as a
/// protocol — exactly like `NotificationScheduling` for `UNUserNotificationCenter`
/// — so unit tests can substitute a mock and verify the iOS-26-vs-fallback
/// branching in `AlarmScheduler` without standing up the real `AlarmManager`
/// (which requires a live iOS 26 device, user authorization, and a registered
/// AppIntent surface).
///
/// Deliberately uses ONLY framework-free types (`Alarm`, `UUID`, `Bool`) in its
/// signatures so the protocol — and the tests that mock it — compile on every
/// iOS version. The concrete `AlarmKitScheduler` is the only `@available(iOS 26)`
/// surface.
protocol AlarmKitScheduling: AnyObject {
    /// Whether AlarmKit reports the user has authorized scheduling alarms.
    var isAuthorized: Bool { get }

    /// Request AlarmKit authorization. Completes with `true` when authorized.
    /// Idempotent — AlarmKit returns the cached state once decided.
    func requestAuthorization(completion: @escaping (Bool) -> Void)

    /// Schedule (or replace) the system alarm for `alarm`. Throws when AlarmKit
    /// rejects the request (limit reached, not authorized). A no-op for a
    /// disabled alarm is the caller's responsibility.
    func schedule(_ alarm: Alarm) throws

    /// Reschedule `alarm` as a one-shot AlarmKit system alarm that re-fires at
    /// `fireDate` (the snooze re-ring), `.never` recurrence. Reuses the alarm's
    /// id so the snooze replaces the just-stopped firing (#383). Throws when
    /// AlarmKit rejects the request. Kept distinct from `schedule(_:)` because a
    /// snooze fires at an arbitrary wall-clock time (now + snoozeMinutes), not at
    /// the alarm's configured time-of-day.
    func scheduleSnooze(_ alarm: Alarm, fireDate: Date) throws

    /// Cancel the system alarm for `alarmID` (pending — not yet alerting).
    func cancel(_ alarmID: UUID)

    /// Stop a currently-alerting system alarm (user tapped stop / snooze).
    func stop(_ alarmID: UUID)
}

#if canImport(AlarmKit)

/// Empty metadata payload. AlarmKit requires the generic `AlarmAttributes` to
/// carry an `AlarmMetadata`; we don't need custom Live Activity data for the
/// core scheduling path (Live Activity / Dynamic Island presentation is
/// explicitly out of scope for #377), so a marker struct satisfies the
/// constraint without shipping unused UI.
@available(iOS 26.0, *)
struct SnoozePayAlarmMetadata: AlarmMetadata {
    init() {}
}

/// Concrete AlarmKit backend. Translates the app's `Alarm` model into an
/// `AlarmManager.AlarmConfiguration` and drives schedule / cancel / stop +
/// authorization. Wires the system alert's stop / snooze buttons to
/// `StopAlarmIntent` / `SnoozeAlarmIntent` so a lock-screen tap routes back
/// into the shared charge / reschedule logic (`AlarmKitActionRouter`).
@available(iOS 26.0, *)
final class AlarmKitScheduler: AlarmKitScheduling {

    private let manager = AlarmManager.shared

    var isAuthorized: Bool {
        manager.authorizationState == .authorized
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        // Already decided? Report synchronously without re-prompting.
        switch manager.authorizationState {
        case .authorized:
            completion(true)
            return
        case .denied:
            completion(false)
            return
        case .notDetermined:
            break
        @unknown default:
            break
        }

        Task {
            do {
                let state = try await manager.requestAuthorization()
                AppLogger.scheduler.notice(
                    "AlarmKit authorization resolved=\(String(describing: state), privacy: .public)"
                )
                await MainActor.run { completion(state == .authorized) }
            } catch {
                AppLogger.scheduler.error(
                    "AlarmKit authorization failed: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run { completion(false) }
            }
        }
    }

    func schedule(_ alarm: Alarm) throws {
        let configuration = try Self.makeConfiguration(for: alarm)
        // `schedule(id:configuration:)` is async; we fire-and-log so the
        // synchronous `AlarmScheduling` contract (used by `AlarmRepository`)
        // is preserved. Errors that surface before the await (config build)
        // are thrown to the caller; post-await failures are logged.
        Task {
            do {
                _ = try await manager.schedule(id: alarm.id, configuration: configuration)
                AppLogger.scheduler.info(
                    "AlarmKit scheduled alarm=\(alarm.id, privacy: .private)"
                )
            } catch {
                let desc = error.localizedDescription
                AppLogger.scheduler.error(
                    "AlarmKit schedule failed alarm=\(alarm.id, privacy: .private): \(desc, privacy: .public)"
                )
            }
        }
    }

    func scheduleSnooze(_ alarm: Alarm, fireDate: Date) throws {
        let configuration = try Self.makeSnoozeConfiguration(for: alarm, fireDate: fireDate)
        // Reuse the alarm's id so the snooze replaces the just-stopped firing —
        // a fresh id would leave the original armed for its next recurrence AND
        // arm a snooze, double-ringing. Fire-and-log mirrors `schedule(_:)` so
        // the synchronous contract holds.
        Task {
            do {
                _ = try await manager.schedule(id: alarm.id, configuration: configuration)
                AppLogger.scheduler.info(
                    "AlarmKit snooze scheduled alarm=\(alarm.id, privacy: .private)"
                )
            } catch {
                let desc = error.localizedDescription
                AppLogger.scheduler.error(
                    "AlarmKit snooze schedule failed alarm=\(alarm.id, privacy: .private): \(desc, privacy: .public)"
                )
            }
        }
    }

    func cancel(_ alarmID: UUID) {
        do {
            try manager.cancel(id: alarmID)
            AppLogger.scheduler.info("AlarmKit cancelled alarm=\(alarmID, privacy: .private)")
        } catch {
            // A not-found cancel is benign (alarm already fired / never armed
            // on this backend) — log at info, never crash the caller.
            let desc = error.localizedDescription
            AppLogger.scheduler.info(
                "AlarmKit cancel no-op alarm=\(alarmID, privacy: .private): \(desc, privacy: .public)"
            )
        }
    }

    func stop(_ alarmID: UUID) {
        do {
            try manager.stop(id: alarmID)
        } catch {
            let desc = error.localizedDescription
            AppLogger.scheduler.info(
                "AlarmKit stop no-op alarm=\(alarmID, privacy: .private): \(desc, privacy: .public)"
            )
        }
    }

    // MARK: - Configuration mapping

    /// Build the AlarmKit configuration for an alarm: schedule (relative time
    /// + weekly recurrence), the full-screen alert presentation (title + stop /
    /// snooze buttons), the stop / snooze intents, and the alarm sound.
    static func makeConfiguration(
        for alarm: Alarm
    ) throws -> AlarmManager.AlarmConfiguration<SnoozePayAlarmMetadata> {
        let schedule = makeSchedule(for: alarm)
        let presentation = makePresentation(for: alarm)
        let attributes = AlarmAttributes<SnoozePayAlarmMetadata>(
            presentation: presentation,
            metadata: SnoozePayAlarmMetadata(),
            tintColor: Color.orange
        )
        return AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: alarm.id),
            secondaryIntent: SnoozeAlarmIntent(alarmID: alarm.id),
            sound: alarmSound(for: alarm)
        )
    }

    /// Build the AlarmKit configuration for a snooze re-fire: same presentation /
    /// intents / sound as the original alarm, but a one-shot schedule pinned to
    /// `fireDate`'s hour/minute (`.never` recurrence) so it rings once at
    /// now + snoozeMinutes instead of the alarm's configured time-of-day (#383).
    static func makeSnoozeConfiguration(
        for alarm: Alarm,
        fireDate: Date
    ) throws -> AlarmManager.AlarmConfiguration<SnoozePayAlarmMetadata> {
        let schedule = makeSnoozeSchedule(fireDate: fireDate)
        let presentation = makePresentation(for: alarm)
        let attributes = AlarmAttributes<SnoozePayAlarmMetadata>(
            presentation: presentation,
            metadata: SnoozePayAlarmMetadata(),
            tintColor: Color.orange
        )
        return AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: alarm.id),
            secondaryIntent: SnoozeAlarmIntent(alarmID: alarm.id),
            sound: alarmSound(for: alarm)
        )
    }

    /// One-shot relative schedule pinned to `fireDate`'s hour/minute. AlarmKit's
    /// relative schedule fires at the next occurrence of that time-of-day; for a
    /// snooze (always < 1h ahead) that next occurrence is the snooze re-ring.
    nonisolated static func makeSnoozeSchedule(fireDate: Date) -> AlarmKit.Alarm.Schedule {
        let components = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
        let time = AlarmKit.Alarm.Schedule.Relative.Time(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
        return .relative(.init(time: time, repeats: .never))
    }

    /// Map the app's hour/minute + Monday-first repeat-day indices to an
    /// AlarmKit relative schedule. A non-repeating alarm uses `.never`
    /// recurrence so it fires once at the next occurrence of the time.
    nonisolated static func makeSchedule(for alarm: Alarm) -> AlarmKit.Alarm.Schedule {
        let components = Calendar.current.dateComponents([.hour, .minute], from: alarm.time)
        let time = AlarmKit.Alarm.Schedule.Relative.Time(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
        let recurrence: AlarmKit.Alarm.Schedule.Relative.Recurrence
        if alarm.repeatDays.isEmpty || alarm.repeatMode != .weekly {
            recurrence = .never
        } else {
            recurrence = .weekly(alarm.repeatDays.compactMap { weekday(forMondayFirstIndex: $0) })
        }
        return .relative(.init(time: time, repeats: recurrence))
    }

    /// Convert a Monday-first 0...6 index (the app's `repeatDays` convention)
    /// to a `Locale.Weekday`. Returns `nil` for out-of-range input so a corrupt
    /// index is dropped rather than crashing — `repeatDays` is already filtered
    /// to 0...6 at the model boundary (#207), so this is belt-and-suspenders.
    nonisolated static func weekday(forMondayFirstIndex index: Int) -> Locale.Weekday? {
        switch index {
        case 0: return .monday
        case 1: return .tuesday
        case 2: return .wednesday
        case 3: return .thursday
        case 4: return .friday
        case 5: return .saturday
        case 6: return .sunday
        default: return nil
        }
    }

    /// Build the full-screen alert presentation. The primary (stop) button is
    /// driven by `stopIntent`; the secondary (snooze) button shows the paid
    /// snooze cost and is driven by `secondaryIntent`.
    private static func makePresentation(for alarm: Alarm) -> AlarmPresentation {
        let snoozeTitle: LocalizedStringResource =
            "Поспать ещё (−\(MoneyFormatter.string(alarm.penalty(forSnoozeCount: 1))))"
        let snoozeButton = AlarmButton(
            text: snoozeTitle,
            textColor: .white,
            systemImageName: "zzz"
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: alarm.name),
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .custom
        )
        return AlarmPresentation(alert: alert)
    }

    /// Resolve the alarm's sound to an AlarmKit alert sound. Falls back to the
    /// system default when the bundled file can't be located.
    private static func alarmSound(for alarm: Alarm) -> ActivityKit.AlertConfiguration.AlertSound {
        if let fileName = AlarmScheduler.shared.alarmSoundFileName(for: alarm.soundID) {
            return .named(fileName)
        }
        return .default
    }
}

#endif
