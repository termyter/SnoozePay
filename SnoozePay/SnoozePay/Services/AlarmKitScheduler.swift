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

    /// Schedule (or replace) the system alarm for `alarm`. A no-op for a
    /// disabled alarm is the caller's responsibility.
    ///
    /// Completion-based — NOT a synchronous `throws` — because the actual
    /// AlarmKit `schedule(id:configuration:)` is `async`: a synchronous API
    /// would have to report success before the await resolves, so an async
    /// rejection (alarm limit, revoked auth, backend reject) would be swallowed
    /// while the caller (`AlarmRepository.save`) already told the user "Будильник
    /// создан" — nothing would ring and no notification fallback would arm
    /// (#417, same phantom-success class as #118/#199 but on the primary iOS 26
    /// path). `completion` fires with `.success` ONLY after the await succeeds,
    /// and `.failure` on any (sync config build or async schedule) error so the
    /// caller can fall through to the notification fallback instead. Mirrors the
    /// `scheduleSnooze` plumbing landed in #394/#401.
    func schedule(
        _ alarm: Alarm,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    /// Reschedule `alarm` as a one-shot AlarmKit system alarm that re-fires once
    /// at `fireDate` (the snooze re-ring), no recurrence. Scheduled under a
    /// SEPARATE snooze id (not `alarm.id`) so a repeating (`.weekly`) original is
    /// left armed for its future occurrences — replacing `alarm.id` would
    /// overwrite the weekly schedule with a one-shot and the alarm would never
    /// ring on its weekdays again (#394). Kept distinct from `schedule(_:)`
    /// because a snooze fires at an arbitrary wall-clock time (now +
    /// snoozeMinutes), not at the alarm's configured time-of-day.
    ///
    /// Completion-based — NOT a synchronous `throws` — because the actual
    /// AlarmKit `schedule` is `async`: a synchronous API would have to report
    /// success before the await resolves, so an async rejection (alarm limit,
    /// revoked auth, backend reject) would be swallowed while the caller has
    /// already charged the snooze penalty and stopped the original — nothing
    /// would ring (#394 Finding 1). `completion` fires with `.success` ONLY after
    /// the await succeeds, and `.failure` on any (sync config or async schedule)
    /// error so the caller can arm the notification-burst fallback instead.
    func scheduleSnooze(
        _ alarm: Alarm,
        fireDate: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    )

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

    func schedule(
        _ alarm: Alarm,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let configuration: AlarmManager.AlarmConfiguration<SnoozePayAlarmMetadata>
        do {
            configuration = try Self.makeConfiguration(for: alarm)
        } catch {
            // Synchronous config-build failure — report immediately so the
            // caller arms the notification fallback (#417).
            let desc = error.localizedDescription
            AppLogger.scheduler.error(
                "AlarmKit schedule config failed alarm=\(alarm.id, privacy: .private): \(desc, privacy: .public)"
            )
            completion(.failure(error))
            return
        }
        let alarmID = alarm.id
        // Report success/failure ONLY after the async schedule resolves, on the
        // main actor (the caller tells the user "Будильник создан" off this
        // result). A swallowed async error here would mean the user sees the
        // alarm as created with nothing armed and no fallback (#417).
        Task {
            do {
                _ = try await manager.schedule(id: alarmID, configuration: configuration)
                AppLogger.scheduler.info(
                    "AlarmKit scheduled alarm=\(alarmID, privacy: .private)"
                )
                await MainActor.run { completion(.success(())) }
            } catch {
                let desc = error.localizedDescription
                AppLogger.scheduler.error(
                    """
                    AlarmKit schedule failed alarm=\(alarmID, privacy: .private): \
                    \(desc, privacy: .public) — fallback
                    """
                )
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func scheduleSnooze(
        _ alarm: Alarm,
        fireDate: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Schedule under a SEPARATE, deterministic snooze id — NOT `alarm.id`.
        // Replacing `alarm.id` would overwrite a `.weekly` original with this
        // one-shot snooze, permanently dropping the recurrence (#394). The
        // caller stops the currently-alerting `alarm.id` before this (#383), so
        // the original weekly stays armed for its next weekday while the snooze
        // rings once.
        let configuration: AlarmManager.AlarmConfiguration<SnoozePayAlarmMetadata>
        do {
            configuration = try Self.makeSnoozeConfiguration(for: alarm, fireDate: fireDate)
        } catch {
            // Synchronous config-build failure — report immediately so the
            // caller arms the notification fallback (#394 Finding 1).
            let desc = error.localizedDescription
            AppLogger.scheduler.error(
                "AlarmKit snooze config failed alarm=\(alarm.id, privacy: .private): \(desc, privacy: .public)"
            )
            completion(.failure(error))
            return
        }
        let snoozeID = Self.snoozeID(for: alarm.id)
        let alarmID = alarm.id
        // Report success/failure ONLY after the async schedule resolves, on the
        // main actor (the caller charges the penalty / arms the fallback off
        // this result). A swallowed async error here would mean the penalty was
        // charged but nothing re-rings (#394 Finding 1).
        Task {
            do {
                _ = try await manager.schedule(id: snoozeID, configuration: configuration)
                AppLogger.scheduler.info(
                    "AlarmKit snooze scheduled alarm=\(alarmID, privacy: .private)"
                )
                await MainActor.run { completion(.success(())) }
            } catch {
                let desc = error.localizedDescription
                AppLogger.scheduler.error(
                    """
                    AlarmKit snooze schedule failed alarm=\(alarmID, privacy: .private): \
                    \(desc, privacy: .public) — fallback
                    """
                )
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func cancel(_ alarmID: UUID) {
        // Cancel both the alarm and any pending snooze re-ring scheduled under
        // its separate snooze id (#394) — otherwise a cancelled alarm could
        // still fire its outstanding snooze.
        cancelOne(alarmID)
        cancelOne(Self.snoozeID(for: alarmID))
    }

    private func cancelOne(_ id: UUID) {
        do {
            try manager.cancel(id: id)
            AppLogger.scheduler.info("AlarmKit cancelled alarm=\(id, privacy: .private)")
        } catch {
            // A not-found cancel is benign (alarm already fired / never armed
            // on this backend) — log at info, never crash the caller.
            let desc = error.localizedDescription
            AppLogger.scheduler.info(
                "AlarmKit cancel no-op alarm=\(id, privacy: .private): \(desc, privacy: .public)"
            )
        }
    }

    func stop(_ alarmID: UUID) {
        // Stop both the alarm and any alerting snooze under its snooze id (#394)
        // so a "stop" from the lock screen silences whichever is ringing.
        stopOne(alarmID)
        stopOne(Self.snoozeID(for: alarmID))
    }

    private func stopOne(_ id: UUID) {
        do {
            try manager.stop(id: id)
        } catch {
            let desc = error.localizedDescription
            AppLogger.scheduler.info(
                "AlarmKit stop no-op alarm=\(id, privacy: .private): \(desc, privacy: .public)"
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
    /// intents / sound as the original alarm, but a one-shot `.fixed` schedule
    /// pinned to the absolute `fireDate` so it rings exactly once at
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

    /// One-shot schedule pinned to the ABSOLUTE `fireDate`. Uses `.fixed` rather
    /// than a relative hour/minute schedule: a relative schedule drops seconds
    /// and fires at the *next* occurrence of that hh:mm, so a snooze planned at
    /// 07:00:30 for +1min (07:01:30) would round to 07:01 — already in the past
    /// this minute — and AlarmKit would take *tomorrow's* 07:01, ~24h away
    /// (#394). `.fixed` rings once at the exact instant, no truncation. (#383)
    ///
    /// `fireDate` is captured by the caller *before* the async schedule await, so
    /// under latency it can already be in the past; a `.fixed` schedule with a
    /// past instant silently never fires (#394 Finding 2). Floor it strictly into
    /// the future first.
    nonisolated static func makeSnoozeSchedule(fireDate: Date) -> AlarmKit.Alarm.Schedule {
        .fixed(flooredSnoozeFireDate(fireDate, now: Date()))
    }

    /// Smallest gap a snooze `fireDate` must keep ahead of `now`; at or under
    /// this we treat it as effectively-past and bump forward so `.fixed` always
    /// fires.
    static let pastDateFloorBuffer: TimeInterval = 2

    /// Clamp a snooze `fireDate` strictly into the future. If `fireDate` is at or
    /// before `now + pastDateFloorBuffer` (latency ate the gap), return
    /// `now + pastDateFloorBuffer` and `.notice`-log the bump; otherwise pass it
    /// through unchanged. Pure + `now`-injectable so the floor is unit-testable
    /// (#394 Finding 2).
    nonisolated static func flooredSnoozeFireDate(_ fireDate: Date, now: Date) -> Date {
        let floor = now.addingTimeInterval(pastDateFloorBuffer)
        guard fireDate <= floor else { return fireDate }
        AppLogger.scheduler.notice(
            """
            AlarmKit snooze fireDate in past/too-soon — \
            bumped forward to now+\(pastDateFloorBuffer, privacy: .public)s
            """
        )
        return floor
    }

    /// Deterministic, distinct snooze id derived from the alarm id (#394). The
    /// AlarmKit snooze re-ring is scheduled under THIS id, not `alarm.id`, so a
    /// `.weekly` original keeps its recurrence instead of being overwritten by a
    /// one-shot. Derived by XOR-ing a fixed namespace into the id's bytes so the
    /// mapping is stable (same alarm → same snooze id) and reversibly cancelable
    /// without persisting any extra state.
    nonisolated static func snoozeID(for alarmID: UUID) -> UUID {
        var bytes = alarmID.uuid
        // Flip the high byte with a fixed marker so the snooze id can never
        // collide with the original alarm id (or any other alarm's id, since the
        // remaining 120 bits stay unique).
        bytes.0 ^= 0x53 // 'S' for Snooze
        return UUID(uuid: bytes)
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
