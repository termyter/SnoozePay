import Foundation
import os
#if canImport(AlarmKit)
import AlarmKit
#endif

// MARK: - #379: foreground custom firing screen for AlarmKit alarms
//
// When an AlarmKit alarm fires while the app is already in the foreground (or
// while it becomes active during the alert window) iOS still owns the system
// alert presentation, but our app process is alive and able to mount its own
// UI on top of its own window. `AlarmManager.shared.alarmUpdates` is an
// `AsyncSequence<[Alarm], Never>` that yields the full alarm set on every
// state change; an alarm in `.alerting` state is one that is currently
// ringing. We watch that stream and present `AlarmFiringViewController` for
// each newly-alerting alarm, de-duplicating so a repeated snapshot (the stream
// re-emits the whole array) doesn't re-present the same firing.
//
// We do NOT and cannot suppress the system lock-screen alert — that's an iOS
// limitation documented in #379. This only adds our screen on the foreground
// app window; it's the AlarmKit analogue of `AppDelegate.willPresent` for the
// notification backend.

/// Source of currently-alerting alarm IDs. Protocol seam so the observer's
/// dedup + present logic is unit-testable without a live `AlarmManager` (which
/// needs an iOS-26 device + authorization). The production conformer wraps
/// `AlarmManager.shared.alarmUpdates`; tests feed a hand-built stream.
protocol AlertingAlarmStream {
    /// An async stream of the *set* of alarm IDs currently in the alerting
    /// state, re-emitted whenever AlarmKit reports any alarm state change.
    func alertingAlarmIDs() -> AsyncStream<Set<UUID>>
}

/// Observes alerting AlarmKit alarms and presents the app's custom firing
/// screen for each one as it begins ringing. Framework-free at the type level
/// (only `UUID` in its API) so the test target compiles on any host; the
/// `AlarmManager`-backed stream is the only iOS-26-gated surface.
@MainActor
final class AlarmKitAlertObserver {

    static let shared = AlarmKitAlertObserver()

    private let stream: AlertingAlarmStream?
    /// Closure invoked with each newly-alerting alarm ID. Injectable so tests
    /// can capture presentations; production presents the firing screen.
    /// `@MainActor` because the only caller (`handle`) is main-actor isolated
    /// and the production closure presents a VC.
    private let onAlerting: @MainActor (UUID) -> Void

    /// Alarm IDs we've already presented for this alerting episode. Cleared as
    /// an alarm leaves the alerting set so a later re-fire of the same alarm
    /// presents again.
    private var presentedAlertingIDs: Set<UUID> = []

    private var task: Task<Void, Never>?

    #if DEBUG
    init(
        stream: AlertingAlarmStream? = AlarmKitAlertObserver.makeDefaultStream(),
        onAlerting: @escaping @MainActor (UUID) -> Void = { AlarmFiringPresenter.shared.present(alarmID: $0) }
    ) {
        self.stream = stream
        self.onAlerting = onAlerting
    }
    #else
    private init(
        stream: AlertingAlarmStream? = AlarmKitAlertObserver.makeDefaultStream(),
        onAlerting: @escaping @MainActor (UUID) -> Void = { AlarmFiringPresenter.shared.present(alarmID: $0) }
    ) {
        self.stream = stream
        self.onAlerting = onAlerting
    }
    #endif

    /// Build the production stream when AlarmKit is available on this OS, else
    /// `nil` (iOS < 26 — there are no AlarmKit alarms to observe). `nonisolated`
    /// so it can be evaluated as a default argument outside the main actor.
    private nonisolated static func makeDefaultStream() -> AlertingAlarmStream? {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManagerAlertingStream()
        }
        #endif
        return nil
    }

    /// Begin observing. Idempotent — a second call while already running is a
    /// no-op so AppDelegate / SceneDelegate can both arm it without
    /// coordinating. No-op when there's no stream (iOS < 26).
    func start() {
        guard task == nil, let stream else { return }
        AppLogger.scheduler.info("AlarmKit alert observer started")
        task = Task { [weak self] in
            for await alertingIDs in stream.alertingAlarmIDs() {
                guard let self else { return }
                await self.handle(alertingIDs: alertingIDs)
            }
        }
    }

    /// Stop observing and reset dedup state.
    func stop() {
        task?.cancel()
        task = nil
        presentedAlertingIDs.removeAll()
    }

    /// Diff the latest alerting set against what we've already presented:
    /// present each newly-alerting alarm exactly once, and forget alarms that
    /// have stopped alerting so a future re-fire presents again. Internal so
    /// tests can drive it directly with synthetic snapshots.
    func handle(alertingIDs: Set<UUID>) {
        // Drop IDs that are no longer alerting so they can re-present later.
        presentedAlertingIDs.formIntersection(alertingIDs)

        let newlyAlerting = alertingIDs.subtracting(presentedAlertingIDs)
        for alarmID in newlyAlerting {
            presentedAlertingIDs.insert(alarmID)
            AppLogger.scheduler.notice(
                "AlarmKit foreground alerting alarm=\(alarmID, privacy: .private) — presenting firing screen"
            )
            onAlerting(alarmID)
        }
    }
}

#if canImport(AlarmKit)

/// Production `AlertingAlarmStream` over `AlarmManager.shared.alarmUpdates`.
/// Maps each `[Alarm]` snapshot to the set of ids whose `state == .alerting`.
@available(iOS 26.0, *)
private struct AlarmManagerAlertingStream: AlertingAlarmStream {
    func alertingAlarmIDs() -> AsyncStream<Set<UUID>> {
        AsyncStream { continuation in
            let task = Task {
                for await alarms in AlarmManager.shared.alarmUpdates {
                    let alerting = Set(
                        alarms.filter { $0.state == .alerting }.map(\.id)
                    )
                    continuation.yield(alerting)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#endif
