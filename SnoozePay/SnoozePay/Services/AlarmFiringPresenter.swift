import UIKit
import os

/// Presents the app's custom alarm-firing screen (`AlarmFiringViewController`)
/// for a given alarm. Extracted from `AppDelegate` so the SAME presentation
/// path serves every trigger source without duplication:
///
///   * notification banner tap / foreground delivery (`AppDelegate`, the
///     original caller — routes through `present(payload:)`),
///   * AlarmKit alert Stop / Snooze buttons (`AlarmKitActionRouter`, #379),
///   * AlarmKit foreground alerting updates (`AlarmKitAlertObserver`, #379).
///
/// The AlarmKit paths only know an `alarmID` (the system replays the intent /
/// the `alarmUpdates` stream yields `Alarm` structs keyed by id), so the
/// entry point resolves the alarm from `AlarmRepository` and builds a
/// zero-snooze firing screen. The notification path keeps its richer payload
/// (snoozeCount, volume) via `present(payload:)`.
///
/// `@MainActor`-isolated because it walks the UIKit view-controller hierarchy
/// and presents a VC — the same isolation the callers (`AppDelegate`
/// notification delegate, AppIntent `perform()`, the alarmUpdates `Task`) run
/// under.
@MainActor
final class AlarmFiringPresenter {

    static let shared = AlarmFiringPresenter(alarmRepository: .shared)

    private let alarmRepository: AlarmRepository

    /// An alarm an AlarmKit alert button (or the alerting observer) asked us to
    /// present but which we couldn't mount yet because no foreground window/root
    /// existed: the system runs the intent before the scene is active, and on a
    /// cold launch the splash → tab-bar root only mounts ~200 ms later. Recorded
    /// by `requestPresentation(alarmID:)` and flushed by
    /// `flushPendingPresentation()` once the scene becomes active, so the firing
    /// screen survives both a warm-foreground race and a cold start (#382).
    /// `private(set)` so tests can assert the deferred id without poking the
    /// internals through reflection.
    private(set) var pendingAlarmID: UUID?

    /// `true` when the real app root (not the launch splash) is mounted and the
    /// firing screen can be presented. Seam so the pending-present retry (#382)
    /// is unit-testable without a UIKit window; production reads the live scene.
    var isRootReady: () -> Bool = { AlarmFiringPresenter.isLaunchRootReady() }

    /// Mounts the firing screen for `alarmID`, returning `false` only when there
    /// was no window to present on (the retry signal). Seam so the pending /
    /// flush logic is unit-testable without standing up the VC hierarchy;
    /// production points at the real `present(alarmID:snoozeCount:)`.
    lazy var mount: (UUID, Int) -> Bool = { [weak self] alarmID, snoozeCount in
        self?.present(alarmID: alarmID, snoozeCount: snoozeCount) ?? false
    }

    // Explicit (no defaulted-argument) init: a `= .shared` default on a
    // `@MainActor` init is evaluated in the *caller's* isolation and trips a
    // "main actor-isolated static property can not be referenced from a
    // nonisolated context" warning at the `static let shared` initializer (#382).
    #if DEBUG
    init(alarmRepository: AlarmRepository) {
        self.alarmRepository = alarmRepository
    }
    #else
    private init(alarmRepository: AlarmRepository) {
        self.alarmRepository = alarmRepository
    }
    #endif

    // MARK: - Pending-present entry point (#382)

    /// Request the firing screen for `alarmID` from a context that may run
    /// before any foreground window exists — the AlarmKit alert buttons
    /// (`AlarmKitActionRouter`, whose intents set `openAppWhenRun`) and the
    /// alerting observer. Records the id as pending and attempts an immediate
    /// present; if no scene/root is attached yet (cold launch, or the foreground
    /// transition hasn't completed) the present is a no-op and the recorded id
    /// is flushed later by `flushPendingPresentation()` from
    /// `SceneDelegate.sceneDidBecomeActive`. This is what makes tapping an
    /// AlarmKit alarm actually open the app *and* land on our screen (#382) —
    /// presenting directly in the intent's `perform()` lost the race and the
    /// screen never appeared.
    func requestPresentation(alarmID: UUID, snoozeCount: Int = 0) {
        pendingAlarmID = alarmID
        attemptPendingPresentation(snoozeCount: snoozeCount)
    }

    /// Mount any deferred firing screen now that the scene is active. Called
    /// from `SceneDelegate.sceneDidBecomeActive` (and after the splash → root
    /// transition completes). Clears the pending id only once the present
    /// actually lands so a still-too-early flush keeps retrying on the next
    /// activation. No-op when nothing is pending.
    func flushPendingPresentation() {
        attemptPendingPresentation()
    }

    /// Try to mount the pending firing screen, but only once the *real* app
    /// root (tab bar / onboarding) is up — not the transient splash. Presenting
    /// over the splash would have the screen torn down the instant the splash
    /// swaps the window's root, so we keep the id pending until the launch
    /// transition completes and re-attempt then. Clears the pending id only
    /// after a successful present (#382).
    private func attemptPendingPresentation(snoozeCount: Int = 0) {
        guard let alarmID = pendingAlarmID else { return }
        guard isRootReady() else {
            AppLogger.appDelegate.notice(
                "firing-present: launch root not ready — deferring alarm \(alarmID, privacy: .private)"
            )
            return
        }
        if mount(alarmID, snoozeCount) {
            pendingAlarmID = nil
        }
    }

    // MARK: - Entry points

    /// Present the firing screen for the alarm identified by `alarmID`,
    /// resolving its model from the repository. Used by the AlarmKit paths
    /// (#379) which only carry the id. A missing / corrupt alarm is logged and
    /// the audio is silenced so the user is never left with a sounding alarm
    /// and no screen — mirroring `AppDelegate.presentAlarmFiringScreen`.
    ///
    /// Returns `true` when a firing screen was mounted (or the alarm was
    /// resolved-but-missing, a terminal outcome that must not be retried), and
    /// `false` only when there was no window to present on — the single signal
    /// the pending-present retry (#382) keys off.
    @discardableResult
    func present(alarmID: UUID, snoozeCount: Int = 0) -> Bool {
        let alarm: Alarm?
        do {
            alarm = try alarmRepository.fetchChecked(id: alarmID)
        } catch {
            let errorDesc = String(describing: error)
            AppLogger.appDelegate.error(
                "firing-present: fetch failed for \(alarmID, privacy: .private): \(errorDesc, privacy: .public)"
            )
            AudioService.shared.stopAlarmSound()
            return true
        }
        guard let alarm else {
            AppLogger.appDelegate.error(
                "firing-present: alarm \(alarmID, privacy: .private) not found — stopping audio"
            )
            AudioService.shared.stopAlarmSound()
            return true
        }
        return present(alarm: alarm, snoozeCount: snoozeCount)
    }

    /// Present the firing screen for an already-resolved alarm. The single
    /// place that builds + mounts `AlarmFiringViewController`, so every trigger
    /// source shares the "dismiss any stale firing screen first, then present
    /// full-screen on the topmost VC" behaviour.
    ///
    /// Returns `false` when no foreground window exists yet (cold-launch race)
    /// so the AlarmKit pending-present (#382) knows to retry on scene-active;
    /// `true` once the present has been issued.
    @discardableResult
    func present(alarm: Alarm, snoozeCount: Int = 0) -> Bool {
        guard let topVC = Self.topViewController() else {
            AppLogger.appDelegate.error("firing-present: no window scene, stopping audio")
            AudioService.shared.stopAlarmSound()
            return false
        }

        let firingVC = AlarmFiringViewController(alarm: alarm, snoozeCount: snoozeCount)
        firingVC.modalPresentationStyle = .fullScreen

        // If an alarm firing screen is already showing, swap it for this one so
        // a stacking alarm (or a re-entry from a different trigger source for
        // the same firing) doesn't trip "already presenting".
        if let presentedFiring = Self.presentedFiringScreen(from: topVC) {
            presentedFiring.dismiss(animated: false) {
                Self.topViewController()?.present(firingVC, animated: false)
            }
            return true
        }

        topVC.present(firingVC, animated: false)
        return true
    }

    // MARK: - Hierarchy walk

    /// `true` once the active window scene's root is the *real* app UI rather
    /// than the transient launch splash. The pending-present retry (#382) gates
    /// on this so a deferred firing screen isn't mounted over the splash only to
    /// be torn down when the splash swaps the window's root. Returns `false`
    /// when no scene/window is attached yet (cold-launch race) or the splash is
    /// still showing.
    private static func isLaunchRootReady() -> Bool {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let rootVC = windowScene.windows.first?.rootViewController
        else {
            return false
        }
        return !(rootVC is SplashViewController)
    }

    /// Topmost presented VC of the active foreground window scene, or `nil`
    /// when no scene/window is attached yet (cold-launch race).
    private static func topViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let rootVC = windowScene.windows.first?.rootViewController
        else {
            return nil
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }

    /// Returns the currently-presented `AlarmFiringViewController` anywhere up
    /// the presentation chain rooted at `topVC`, if one is on screen.
    private static func presentedFiringScreen(from topVC: UIViewController) -> UIViewController? {
        var vc: UIViewController? = topVC
        while let current = vc {
            if current is AlarmFiringViewController { return current }
            vc = current.presentingViewController
        }
        return nil
    }
}
