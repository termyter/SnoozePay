import Foundation
import os
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - AlarmKit alert button intents (#377, routing reworked in #379)
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
// #379: both intents set `openAppWhenRun`, so tapping either *button* on the
// system alert foregrounds the app and routes to our custom firing screen
// (`AlarmFiringViewController`) for that alarm via `AlarmKitActionRouter` —
// rather than charging / dismissing silently from the lock-screen context.
// The in-app firing screen owns the actual stop / paid-snooze flow, so the
// charge / reschedule logic is NOT duplicated in the intents. Both carry the
// alarm UUID as a plain string parameter so the system can persist + replay
// them; the router resolves the alarm from `AlarmRepository` when presenting.
//
// #382: presenting our screen directly inside `perform()` lost a window race —
// `openAppWhenRun` foregrounds the app, but `perform()` runs *before* the scene
// is active (and on a cold launch the splash → tab-bar root mounts ~200 ms
// later), so the present silently no-op'd and the user only ever saw the app
// background. The router now hands the alarm id to
// `AlarmFiringPresenter.requestPresentation`, which records it as *pending* and
// flushes it from `SceneDelegate.sceneDidBecomeActive`. The presentation
// therefore survives both the warm-foreground race and a cold start.
//
// What `openAppWhenRun` can / cannot do (verified against the public AlarmKit /
// AppIntents surface, iOS 26): it reliably foregrounds the app when the user
// taps a *button* (Stop / Snooze) whose `LiveActivityIntent` we own. The public
// API does NOT expose a way to attach an intent to a tap on the *body* of the
// system alert / Dynamic Island — that gesture is system-owned and is not
// guaranteed to run our intent. So the supported "tap to open our screen" path
// is the alert's buttons; tapping the body alone may not route. Both buttons
// are wired, so any deliberate user action on the alarm opens the app.
//
// NOTE: iOS does not allow replacing the system alert at fire time on a locked
// screen with our own UIView — that presentation stays system-owned. Our screen
// only appears once the app is brought to the foreground (#379 scope).

#if canImport(AppIntents)

@available(iOS 26.0, *)
struct StopAlarmIntent: LiveActivityIntent {

    /// Read from the catalogue rather than written as a literal: a
    /// `LocalizedStringResource` built from a literal uses the literal as its
    /// lookup key, which no entry matches (`AlarmKitCopy`).
    static var title: LocalizedStringResource { AlarmKitCopy.stopTitle }

    /// Bring the app to the foreground when the system runs this intent so the
    /// router can present our custom firing screen (#379). Without this the
    /// intent silences the alarm but the user never sees our screen — the
    /// issue's whole point is to route an alarm-open to the in-app flow rather
    /// than only dismissing the system UI.
    static let openAppWhenRun: Bool = true

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

    /// See `StopAlarmIntent.title`. The alert's secondary *button* shows the
    /// priced variant built in `AlarmKitScheduler.makePresentation`; this is
    /// the intent's own name, which Shortcuts also displays.
    static var title: LocalizedStringResource { AlarmKitCopy.snoozeTitle }

    /// Open the app so the paid-snooze flow runs in our firing screen (#379)
    /// rather than charging silently from the lock screen. See `StopAlarmIntent`.
    static let openAppWhenRun: Bool = true

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
/// from the intents so the routing decision is unit-testable without standing
/// up AppIntents / AlarmKit — the intents are thin shells whose only job is to
/// forward to this type.
///
/// Always available (no `@available` gate) so the test target and the
/// `< iOS 26` build can reference it; the intents that call it are the
/// iOS-26-gated surface.
///
/// ## #379 — route an alarm-open into our custom firing screen
///
/// Both alert buttons set `openAppWhenRun`, so the system foregrounds the app
/// before running `perform()`. Rather than charging / dismissing from the
/// lock-screen context, the router silences the system alarm UI and then hands
/// off to `AlarmFiringPresenter`, which mounts our `AlarmFiringViewController`
/// for that alarm. The in-app firing screen owns the actual stop / paid-snooze
/// flow (via `AlarmFiringViewModel` → `AlarmFiringCoordinator`), so the charge
/// / refund logic is NOT duplicated here — the lock-screen button can't tell
/// us the live snoozeCount or run an Apple-Pay top-up anyway.
///
/// `@MainActor`-isolated: it silences `AudioService`, stops the system alarm
/// via `AlarmScheduler`, and presents a VC through `AlarmFiringPresenter` —
/// all main-actor surfaces, matching the main-actor `perform()` that drives it.
@MainActor
final class AlarmKitActionRouter {

    static let shared = AlarmKitActionRouter()

    /// Seam so a test can observe which alarmID the router asked to present
    /// without standing up the UIKit hierarchy. Defaults to the real presenter's
    /// *pending-present* entry point: the system runs the intent before the
    /// scene is active (and may cold-launch the app), so presenting directly
    /// here loses the window race and the screen never appears (#382).
    /// `requestPresentation` records the id and retries on scene-active.
    var present: (UUID) -> Void = { alarmID in
        AlarmFiringPresenter.shared.requestPresentation(alarmID: alarmID)
    }

    #if DEBUG
    init() {}
    #else
    private init() {}
    #endif

    /// Stop button on the system alert. Silence audio, dismiss the system alarm
    /// UI, then open our firing screen so the user confirms the wake in-app
    /// (the in-app dismiss records the wake day, mirroring the notification
    /// `DISMISS_ACTION` semantics). The screen is the single owner of the wake
    /// event so a Stop that the user then changes their mind on (snoozes
    /// in-app) isn't double-counted.
    func handleStop(alarmIDString: String) {
        guard let alarmID = UUID(uuidString: alarmIDString) else {
            AppLogger.scheduler.error(
                "AlarmKit stop: malformed alarmID \(alarmIDString, privacy: .public)"
            )
            return
        }
        AppLogger.scheduler.notice("AlarmKit stop alarm=\(alarmID, privacy: .private)")
        AudioService.shared.stopAlarmSound()
        // Stop the AlarmKit alert itself so the system stops the alarm UI.
        AlarmScheduler.shared.stopSystemAlarm(alarmID)
        present(alarmID)
    }

    /// Snooze button on the system alert. Silence the system alarm UI, then
    /// open our firing screen so the *paid* snooze (−X ₽, progressive penalty,
    /// Apple-Pay top-up on insufficient balance) runs through the in-app flow
    /// — the same path the notification banner takes. The charge therefore
    /// happens exactly once, in the screen, never from the lock-screen button
    /// (which can't surface a balance error or a top-up sheet).
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
        present(alarmID)
    }
}
