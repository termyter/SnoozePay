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

    /// Where the firing screen gets mounted: the topmost controller of the
    /// window ``ActiveWindowLocator`` picked, or the ``ActiveWindowLocator/Miss``
    /// saying why there is none.
    ///
    /// Seam for the same reason ``isRootReady`` is one — the real walk reads
    /// `UIApplication.shared.connectedScenes`, which a unit test cannot stage.
    /// What it buys is the loudest branch this class has: audio silenced and no
    /// screen raised, whose only evidence is one log line. Before #795 nothing
    /// in the suite reached it, so deleting the line, the `stopAlarmSound()` or
    /// the `return false` left the target green.
    ///
    /// The default closure is the residue: with a test seam installed nothing
    /// evaluates it, so it is one unobservable line instead of an unobservable
    /// branch — the same trade ``AppLogger/emit(_:_:_:)`` documents one level
    /// down.
    var locateHost: () -> Result<UIViewController, ActiveWindowLocator.Miss> = {
        AlarmFiringPresenter.locatedTopViewController()
    }

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
    /// Returns `false` when nothing can host the presentation yet — no scene,
    /// no windows, or no window carrying a root (the cold-launch race) — so the
    /// AlarmKit pending-present (#382) knows to retry on scene-active; `true`
    /// once the present has been issued. Which of the three it was goes to the
    /// log, because they are not fixed the same way.
    @discardableResult
    func present(alarm: Alarm, snoozeCount: Int = 0) -> Bool {
        let topVC: UIViewController
        switch locateHost() {
        case let .success(located):
            topVC = located
        case let .failure(miss):
            // The reason is the locator's: "no window scene" was true of only
            // one of the three states this returns on, and the loudest one —
            // audio stopped, screen never raised — is the state where a scene
            // and windows exist but none of them can host a presentation.
            //
            // Through `AppLogger.emit` rather than `AppLogger.appDelegate`
            // because this line IS the outcome: nothing else records that an
            // alarm was silenced without a screen. A line only unified logging
            // can see is a line no test reads, and #795 found this one
            // unreferenced by the whole suite. `miss.rawValue` is a fixed
            // sentence, so `emit`'s implicit `.public` is the marker it already
            // carried.
            AppLogger.emit(
                .appDelegate, .error,
                "firing-present: \(miss.rawValue) — stopping audio"
            )
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
        guard case let .success(rootVC) = ActiveWindowLocator.rootViewController() else {
            return false
        }
        return !(rootVC is SplashViewController)
    }

    /// Topmost presented VC of the window the locator picked, or the
    /// ``ActiveWindowLocator/Miss`` saying which of the three "nothing to
    /// present on" states was hit — so `present` can name the one it stopped
    /// the audio for instead of blaming the scene for all three. Reached by
    /// `present(alarm:snoozeCount:)` through ``locateHost``.
    private static func locatedTopViewController() -> Result<UIViewController, ActiveWindowLocator.Miss> {
        switch ActiveWindowLocator.rootViewController() {
        case let .failure(miss):
            return .failure(miss)
        case let .success(rootVC):
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            return .success(topVC)
        }
    }

    /// ``locatedTopViewController()`` for the caller that re-resolves the top
    /// VC inside a dismissal completion and has nothing to say about why it
    /// might be gone. Kept as its own one-liner so the reason-carrying form
    /// stays the one used where the miss is logged.
    private static func topViewController() -> UIViewController? {
        try? locatedTopViewController().get()
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
