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
    /// by `requestPresentation(alarmID:snoozeCount:)`, by a request parked
    /// while a swap's dismissal is outstanding (#807), and by
    /// `mountAfterDismissal` whenever the swap's screen did not go up: no host
    /// left (#804), UIKit declined the `present`, the stale screen still up, or
    /// a firing screen already there that is another alarm's or this alarm's
    /// at a lower snooze count (#807). And by the direct present, when UIKit
    /// declines it (#833), when no host is found, or when the root is still
    /// the launch splash (#834). And by a swap, before its dismissal starts
    /// (#835). What a write may replace is `armRetry`'s rule. Flushed by
    /// `flushPendingPresentation()` once the scene becomes active, right after
    /// a swap lands, on the next turn after a host miss (#875), and when a
    /// UIKit transition that refused a present or held a swap ends (#875), so
    /// the firing screen survives both a warm-foreground race and a cold start
    /// (#382).
    ///
    /// The snooze count travels with the id because the retry rebuilds the
    /// screen from this record alone, and the penalty is priced from it
    /// (`penalty(forSnoozeCount: snoozeCount + 1)`). Held as one value rather
    /// than two optionals so the pair cannot come apart: the retry used to
    /// mount with `0`, which put a deferred third snooze back on the first
    /// step's price (#808).
    ///
    /// Read through `pendingPresentations` so tests can assert the deferred
    /// screens without poking the internals through reflection.
    ///
    /// A queue with one record per alarm, not one slot (#858): a slot let the
    /// newest request drop another alarm's record, including the record of the
    /// alarm that owns `AudioService`, which then rang with no screen and no
    /// retry (#869). What a write keeps is still `armRetry`'s rule. The flush
    /// goes in arrival order, so the newest alarm is the one left on screen.
    /// Internal only so `AlarmFiringPresenter+Queue.swift` can reach it (#883).
    var pendingQueue: [QueuedPresentation] = []

    /// The clock the expiry reads. A seam so a test can age a record.
    var now: () -> Date = { Date() }

    /// `true` when the real app root (not the launch splash) is mounted and the
    /// firing screen can be presented. Checked by the pending-present retry
    /// (#382) and by the direct present (#834). Seam so both are unit-testable
    /// without a UIKit window; production reads the live scene.
    var isRootReady: () -> Bool = { AlarmFiringPresenter.isLaunchRootReady() }

    /// Where the firing screen gets mounted: the topmost controller of the
    /// window ``ActiveWindowLocator`` picked, or the ``ActiveWindowLocator/Miss``
    /// saying why there is none.
    ///
    /// Seam for the same reason ``isRootReady`` is one — the real walk reads
    /// `UIApplication.shared.connectedScenes`, which a unit test cannot stage.
    /// What it buys is the loudest branch this class has: no screen raised,
    /// whose only evidence is one log line. Before #795 nothing in the suite
    /// reached it, so deleting the line or the `return false` left the target
    /// green.
    ///
    /// The default closure is the residue: with a test seam installed nothing
    /// evaluates it, so it is one unobservable line instead of an unobservable
    /// branch — the same trade ``AppLogger/emit(_:_:_:)`` documents one level
    /// down.
    var locateHost: () -> Result<UIViewController, ActiveWindowLocator.Miss> = {
        AlarmFiringPresenter.locatedTopViewController()
    }

    /// What the "fetch failed" miss in `present(alarmID:snoozeCount:)` does
    /// besides its log line: put the data-corrupted alert up, through the
    /// same `AppDelegate.reportAlarmDataCorrupted` the notification path uses,
    /// which keeps an identical alert from stacking (#868). Before this, an
    /// AlarmKit alarm whose stored alarms failed to decode ended with its audio
    /// stopped, no screen, and nothing to say why.
    ///
    /// A seam for the same reason ``locateHost`` is one: the default reaches
    /// the live application, and a test replaces it so no alert mounts on the
    /// test host's window. With no `AppDelegate` behind the application the
    /// default logs the dropped alert instead (#872).
    var reportDataCorrupted: (Error) -> Void = { error in
        AppDelegate.forwardAlarmDataCorrupted(error, to: UIApplication.shared.delegate)
    }

    /// Takes the stale firing screen down before the replacement goes up:
    /// `dismiss(animated:completion:)` in production.
    ///
    /// A seam for the same reason ``locateHost`` is one, one step further out.
    /// The swap's second half runs in a completion UIKit calls, so from a test
    /// the whole branch is one call with no return value: what it does after
    /// the dismissal — whether it re-resolves a host at all, and what it does
    /// when there is none (#798) — is unreachable. Holding the completion as a
    /// value makes both of its outcomes reachable, and running it is the test's
    /// stand-in for "the dismissal finished".
    ///
    /// Sent to the screen's presenter, not the screen: `dismiss` on a
    /// controller that is itself presenting something — the top-up sheet, a
    /// refund alert, the WokeMorning summary left up after Stop — takes down
    /// only what it presented and leaves it standing (#807). Only while that
    /// presenter still presents it: see `dismissFromItsPresenter`.
    var dismissStaleScreen: (UIViewController, @escaping () -> Void) -> Void = { staleScreen, completion in
        AlarmFiringPresenter.dismissFromItsPresenter(staleScreen, completion: completion)
    }

    /// `dismissStaleScreen`'s production body (#875, FU-2).
    ///
    /// `dismiss` on a controller with nothing presented takes that controller
    /// down itself. So a presenter whose `presentedViewController` is no longer
    /// the stale screen (nil at the end of a transition, or another modal)
    /// would lose itself or that modal: the alarm-edit sheet with its unsaved
    /// changes. The stale screen is then off the presenter already, so no
    /// dismissal is sent and the swap goes on. When the screen is still in
    /// the walk, `mountAfterDismissal`'s stale-survival retry takes it.
    ///
    /// With no presenter (a firing screen that is a window's root, as in the
    /// UI-tour routes) the screen itself gets it, as before: that takes down
    /// only what it presented.
    static func dismissFromItsPresenter(_ staleScreen: UIViewController, completion: @escaping () -> Void) {
        guard let presenter = staleScreen.presentingViewController else {
            staleScreen.dismiss(animated: false, completion: completion)
            return
        }
        guard presenter.presentedViewController === staleScreen else {
            AppLogger.emit(
                .appDelegate, .default,
                "firing-present: \(type(of: presenter)) no longer presents the previous screen"
                    + " — not sending it the dismissal"
            )
            completion()
            return
        }
        presenter.dismiss(animated: false, completion: completion)
    }

    /// Runs its closure once the UIKit transition the controller takes part in
    /// has ended, answering `false` without running it when none is in flight
    /// (#875). UIKit refuses a `present` on a controller in a transition and
    /// drops a `dismiss` issued during one without running its completion, so
    /// the retry for either waits for the end of that transition: the next
    /// main-queue turn is still inside it, and the activation never comes
    /// while the app stays foreground.
    ///
    /// `transitionCoordinator` also answers for a controller whose presented
    /// sheet is coming or going. A seam because a unit test cannot stage a
    /// live transition. A stand-in holds the closure for later, as UIKit
    /// does, and must not run it inside the call.
    var whenTransitionEnds: (UIViewController, @escaping () -> Void) -> Bool = { controller, body in
        guard let coordinator = controller.transitionCoordinator else { return false }
        return coordinator.animate(alongsideTransition: nil) { _ in body() }
    }

    /// Builds the firing screen `present(alarm:snoozeCount:)` mounts.
    ///
    /// A seam for the read-back after the swap's `present` (#807): UIKit sets
    /// the screen's `presentingViewController` only when it really presents,
    /// which in a unit test means a window and a full UIKit presentation. With
    /// this, a test double for the host can answer the read-back the way UIKit
    /// does — by wiring the screen it accepted — instead of the read-back being
    /// swapped for something a double can fake more easily.
    var makeFiringScreen: (Alarm, Int) -> AlarmFiringViewController = { alarm, snoozeCount in
        AlarmFiringViewController(alarm: alarm, snoozeCount: snoozeCount)
    }

    /// The stale firing screen a swap is taking down, until its dismissal
    /// completion runs (#807).
    ///
    /// Between `dismissStaleScreen` and its completion the alarm is still
    /// pending, so a `sceneDidBecomeActive` flush or a second trigger source
    /// re-enters `present(alarm:)`, finds this same screen and would dismiss it
    /// a second time. Matched by identity against the screen the hierarchy
    /// walk finds rather than held as a flag, and honoured only while UIKit
    /// still reports that screen `isBeingDismissed`: a marker cleared only in
    /// a completion UIKit may never call would otherwise refuse every later
    /// alarm. Weak for the same reason.
    private weak var screenBeingDismissed: AlarmFiringViewController?

    /// Re-attempts spent on a stale screen that outlived its own dismissal,
    /// since the last screen that went up. Bounds that retry: nothing in the
    /// hierarchy guarantees each dismissal removes a layer, and a completion
    /// that removes nothing would otherwise re-swap on every main-queue turn —
    /// an `.error` line and a fresh screen each time, all night (#807 review).
    private var staleSurvivalRetries = 0

    /// Enough for a stale screen with one layer on it (dismissal takes the
    /// layer, the retry takes the screen) plus one spare.
    static let staleSurvivalRetryLimit = 2

    /// Re-attempts spent on a host miss, in `present` or after a swap's
    /// dismissal, since the last screen that went up (#875). In the foreground
    /// nothing else raises the alarm before the next activation.
    /// Internal only so `AlarmFiringPresenter+Queue.swift` can reach it (#883).
    var hostGoneRetries = 0

    /// The host is usually back on the next turn. Gone for good, the retry
    /// stops at the root gate, which reads the same locator; the bound covers
    /// a firing screen found on every turn and no host after every dismissal.
    static let hostGoneRetryLimit = 2

    /// Mounts the firing screen for `alarmID`, returning `false` when the screen
    /// is not up by the time it returns (the retry signal). Seam so the pending /
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

    /// The record this flush, or a swap's completion, raised while more were
    /// queued. The next record swaps its screen out, and that loss is an
    /// `.error` (#858 review, #875).
    /// Internal only so `AlarmFiringPresenter+Queue.swift` can reach it (#883).
    var raisedFromQueue: PendingPresentation?

    // MARK: - Entry points

    /// Present the firing screen for the alarm identified by `alarmID`,
    /// resolving its model from the repository. Used by the AlarmKit paths
    /// (#379) which only carry the id, and by the pending slot's `mount`. A
    /// missing / corrupt alarm is logged, and only the sound that alarm itself
    /// owns is stopped: see `stopAudio(ifOwnedBy:_:)`. A corrupt one is also
    /// reported through ``reportDataCorrupted`` (#868).
    ///
    /// Returns `true` when a firing screen was mounted (or the alarm was
    /// resolved-but-missing, a terminal outcome that must not be retried), and
    /// `false` when it was not up by the time this returned — the signal the
    /// pending-present retry (#382) keys off. See `present(alarm:snoozeCount:)`
    /// for the two states behind that `false`.
    @discardableResult
    func present(alarmID: UUID, snoozeCount: Int = 0) -> Bool {
        let request = PendingPresentation(alarmID: alarmID, snoozeCount: snoozeCount)
        let alarm: Alarm?
        do {
            alarm = try alarmRepository.fetchChecked(id: alarmID)
        } catch {
            stopAudio(ifOwnedBy: request, "fetch failed (\(String(describing: error)))")
            reportDataCorrupted(error)
            return true
        }
        guard let alarm else {
            stopAudio(ifOwnedBy: request, "not found")
            return true
        }
        return present(alarm: alarm, snoozeCount: snoozeCount)
    }

    /// Present the firing screen for an already-resolved alarm. The single
    /// place that builds + mounts `AlarmFiringViewController`, so every trigger
    /// source shares the "dismiss any stale firing screen first, then present
    /// full-screen on the topmost VC" behaviour.
    ///
    /// Returns `true` only when the screen reads back as up by the time it
    /// returns. `false` covers four ways that can fail to happen: nothing can
    /// host the presentation yet — no scene, no windows, or no window carrying
    /// a root (the cold-launch race), which of the three goes to the log
    /// because they are not fixed the same way — the root still being the
    /// launch splash, the re-entry swap below, which cannot finish before its
    /// dismissal completion runs, and UIKit declining the direct `present`
    /// (#833). Each of them leaves the request in the pending slot itself, so
    /// a caller that discards the answer — the notification path — still gets
    /// the retry (#834). The swap included: it parks the request before the
    /// dismissal starts, and its completion (`mountAfterDismissal`) clears it
    /// once the screen reads back as up (#807) or re-arms it when it could not
    /// raise it (#798). A dismissal UIKit never completes leaves the request
    /// parked for the next activation (#835), behind any other alarm's (#858).
    ///
    /// `true` without mounting when this alarm's screen is up and still
    /// ringing at a count no lower than the request's: `settleOnRingingScreen`.
    @discardableResult
    func present(alarm: Alarm, snoozeCount: Int = 0) -> Bool {
        let request = PendingPresentation(alarmID: alarm.id, snoozeCount: snoozeCount)
        let topVC: UIViewController
        switch locateHost() {
        case let .success(located):
            topVC = located
        case let .failure(miss):
            // The reason is the locator's (#795): "no window scene" was true
            // of only one of the three states this returns on.
            //
            // Parked and re-armed here, not left to the caller: the
            // notification path discards the answer (#834), and in the
            // foreground `willPresent` shows no banner for a ringing alarm,
            // so nothing else raises it before the next activation (#875).
            // With no host the retry stops at the root gate (same locator).
            //
            // The audio is left alone (`stopAudio(ifOwnedBy:_:)`'s rule): a
            // silent pending alarm is a missed alarm, the worst outcome here.
            // With its own sound on this is practically unreachable: a
            // foreground scene has a host; the realistic miss is a cold-launch
            // tap before the scene connects, with no in-app sound on. The old
            // unconditional stop silenced another owner's sound (#854/#859).
            //
            // `miss.rawValue` is a fixed sentence, so `emit`'s implicit
            // `.public` (through `armRetry`) is the marker it already carried.
            retryHostMiss(request, "firing-present: \(miss.rawValue)")
            return false
        }

        let firingVC = makeFiringScreen(alarm, snoozeCount)
        firingVC.modalPresentationStyle = .fullScreen
        firingVC.onUserStop = { [weak self, weak firingVC] in
            guard let firingVC else { return }
            self?.discardPending(stopped: PendingPresentation(on: firingVC))
        }

        // If an alarm firing screen is already showing, swap it for this one so
        // a stacking alarm (or a re-entry from a different trigger source for
        // the same firing) doesn't trip "already presenting".
        //
        // The swap finishes in a completion whose timing is UIKit's, so "not
        // mounted yet" is the only answer this function can stand behind; the
        // request is parked before the dismissal and the completion clears it
        // once the screen reads back as up. Answering `true` reported a screen
        // that had not gone up, and when the completion then found no host it
        // never went up at all:
        // `attemptPendingPresentation` had already dropped `pendingAlarmID` on
        // the strength of that `true`, so nothing retried and the alarm went
        // unanswered with no line anywhere (#798).
        if let presentedFiring = Self.presentedFiringScreen(from: topVC) {
            // Re-entry while this very screen is still being taken down (#807):
            // a second `dismiss` on it is not ours to issue, and the screen the
            // first swap mounts is the one the user gets. This request waits in
            // the pending slot — cleared by that mount when it is the same
            // alarm, re-attempted right after it when it is not.
            //
            // Only while UIKit confirms the dismissal: if it dropped it and
            // will never run the completion, the screen stays up and not
            // being dismissed, and a fresh `dismiss` is the way out. A
            // duplicate completion cannot stack, `mountAfterDismissal` checks.
            if presentedFiring === screenBeingDismissed, presentedFiring.isBeingDismissed {
                armRetry(
                    request, level: .default,
                    "firing-present: the previous screen is still being dismissed — keeping this one pending"
                )
                return false
            }
            guard let mismatch = Self.ringMismatch(presentedFiring, for: request) else {
                settleOnRingingScreen(presentedFiring)
                return true
            }
            if deferSwapPastTransition(of: presentedFiring, request) { return false }
            parkBeforeSwap(request, replacing: presentedFiring, because: mismatch)
            // Set before the call so a completion UIKit runs synchronously
            // clears it rather than finding nothing to clear. Leaving a stale
            // marker behind is harmless now that the guard above also needs
            // `isBeingDismissed`, but the marker then names a swap that is over.
            screenBeingDismissed = presentedFiring
            dismissStaleScreen(presentedFiring) { [weak self, weak presentedFiring] in
                guard let self else { return }
                if self.screenBeingDismissed === presentedFiring { self.screenBeingDismissed = nil }
                self.mountAfterDismissal(firingVC, replacing: presentedFiring, retry: request)
            }
            return false
        }

        // The common path — usually no firing screen is up. It answered `true`
        // without looking, and `attemptPendingPresentation` dropped the alarm on
        // that answer: a present UIKit declined (the top still being dismissed
        // or presented, a detached host) lost it with only UIKit's console
        // warning behind (#833). Same read-back as the swap's completion.
        //
        // Not over the launch splash — the gate `attemptPendingPresentation`
        // applies. The splash → root swap tears such a screen down, yet the
        // read-back passes and would clear a record AlarmKit parked for this
        // alarm, so the flush after the swap finds nothing to raise (#834).
        // Parked instead, for that flush. The notification path gets here
        // over the splash on a cold launch by a banner tap; the pending path
        // never does, since it checks the same seam before mounting.
        guard isRootReady() else {
            armRetry(request, level: .default, "firing-present: launch root not ready — keeping it pending")
            return false
        }
        return presentReadingBack(firingVC, on: topVC, request: request, context: "", raiseParked: false)
    }

    /// Holds the swap while `screen` is still coming in or going out, or a
    /// sheet on it is (#875, FU-3): a `dismiss` sent now is dropped with its
    /// completion, and the request would wait for an activation that a
    /// foreground app does not get. The swap is asked again at the end.
    private func deferSwapPastTransition(of screen: AlarmFiringViewController, _ request: PendingPresentation) -> Bool {
        guard retryAfterTransition(of: screen) else { return false }
        armRetry(
            request, level: .default,
            "firing-present: the screen of \(PendingPresentation(on: screen).logHandle)"
                + " is in a transition — swapping it once that ends"
        )
        return true
    }

    /// The swap's own park, before its dismissal starts, so a completion
    /// UIKit never runs leaves the request waiting for the next activation
    /// rather than neither shown nor parked (#835). The completion clears it.
    /// The line names the screen going down: a ringing screen of another
    /// alarm goes silent in its `viewDidDisappear`, and this line is all that
    /// says why.
    ///
    /// Parked behind another alarm's record too, since the queue drops
    /// neither (#858): that record is raised once this swap lands
    /// (`raiseParked`), and this one survives a dismissal UIKit never completes.
    ///
    /// `.error` when the screen going down is another alarm's that the flush
    /// raised from the queue: that alarm is lost to the next record.
    private func parkBeforeSwap(
        _ request: PendingPresentation, replacing screen: AlarmFiringViewController, because mismatch: RingMismatch
    ) {
        let shown = PendingPresentation(on: screen)
        let lost = mismatch == .otherAlarm && shown == raisedFromQueue
        armRetry(
            request, level: lost ? .error : .default,
            "firing-present: swapping out the screen of \(shown.logHandle)"
                + " (\(mismatch.rawValue)\(lost ? ", raised from the queue in this flush" : ""))"
        )
    }

    /// How long after `AlarmFiringViewModel.lastRingStartedAt` (the last
    /// re-ring, else the mount; #855) a screen without its own `AudioService`
    /// sound (AlarmKit) still counts as the request's ring. Second triggers
    /// arrive within a minute; yesterday's screen must be swapped (#835).
    static let currentFiringWindow: TimeInterval = 10 * 60

    /// The same bound while the alarm owns `AudioService`. That sound proves
    /// the request, not the screen: `AppDelegate.startForegroundAlarm` takes
    /// it before `present`. Two firings of one alarm are 24 h apart unless it
    /// is edited, so 3 h keeps a long ring and swaps any earlier firing.
    static let currentRingSoundingLimit: TimeInterval = 3 * 60 * 60

    /// Why a screen is not the request's ring; printed in the swap lines.
    enum RingMismatch: String {
        case otherAlarm = "another alarm"
        case olderCount = "a lower snooze count"
        case dismissing = "being dismissed"
        case stopped = "stopped by the user"
        case snoozed = "snoozed"
        case outsideWindow = "rang too long ago"
        case previousFiring = "from an earlier firing"
        case silent = "its sound is not on"
    }

    /// `nil` when `screen` is `request`'s alarm at its count or above, still
    /// ringing its current ring: the one test of the swap and its completion
    /// (#855). Ringing: this alarm owns `AudioService` in any state but
    /// `.stopped` (a swap kills a vibration-only ring) and its ring started
    /// within `currentRingSoundingLimit`; without that sound, only AlarmKit
    /// can be ringing, inside `currentFiringWindow`.
    private static func ringMismatch(
        _ screen: AlarmFiringViewController, for request: PendingPresentation
    ) -> RingMismatch? {
        let model = screen.viewModel
        if model.alarm.id != request.alarmID { return .otherAlarm }
        if model.snoozeCount < request.snoozeCount { return .olderCount }
        if screen.isBeingDismissed { return .dismissing }
        if screen.isStoppedByUser { return .stopped }
        if screen.isSnoozedStateActive { return .snoozed }
        let sinceRing = Date().timeIntervalSince(model.lastRingStartedAt)
        if AudioService.shared.soundingAlarmID == model.alarm.id {
            return sinceRing <= currentRingSoundingLimit ? nil : .previousFiring
        }
        if !model.usesAlarmKit { return .silent }
        return sinceRing <= currentFiringWindow ? nil : .outsideWindow
    }

    /// Settles on the ringing screen a swap would rebuild and silence (#835).
    /// While this alarm has a record at a higher count anywhere in the queue,
    /// the next turn starts a flush from the queue's head, as on the direct
    /// path (#875). The flush goes oldest first and ends on that higher count.
    private func settleOnRingingScreen(_ screen: AlarmFiringViewController) {
        let shown = PendingPresentation(on: screen)
        AppLogger.emit(
            .appDelegate, .default,
            "firing-present: this alarm's screen is up and ringing — not swapping it [\(shown.logHandle)]"
        )
        clearPending(shownAs: shown)
        runQueueSoonForHigherRecord(of: shown.alarmID)
    }

    /// Second half of the swap above: put `firingVC` up now that the stale
    /// firing screen has gone.
    ///
    /// Re-resolves the host rather than reusing the one `present` found: when
    /// UIKit calls this is UIKit's business, and the window the host came from
    /// can be gone by then — the scene backgrounded, the window detached. That
    /// case is the whole of #798. The old code re-resolved too, through
    /// `Self.topViewController()?`, but an optional chain that evaluates to
    /// nothing leaves no screen, no line and — since `present` had already
    /// answered `true` — no retry either.
    ///
    /// Through ``locateHost`` rather than the static walk so this path answers
    /// to the same seam the branch above does — it was the one place in the
    /// class that went around it.
    ///
    /// `retry` is what gets armed when no host is left: the snooze count
    /// `firingVC` was built with as well as its alarm, or the retry prices
    /// the next snooze from the first step (#808).
    ///
    /// Two more ways the screen can fail to go up here, both #807:
    ///
    ///   * A firing screen is already on top. The stale screen can leave the
    ///     hierarchy before UIKit runs this completion, and a re-entry in that
    ///     gap finds nothing to swap and presents directly. Presenting again
    ///     would stack a second firing screen on it.
    ///   * UIKit declines the `present` — read back in
    ///     `presentReadingBack`, which the direct path shares (#833).
    ///
    /// `staleScreen` is the screen this swap dismissed. Found on top again, or
    /// still `isBeingDismissed`, it is not "up": it survived its own dismissal
    /// or is going away, and taking it for this alarm's screen would clear the
    /// alarm with nothing new on screen. Re-armed and re-attempted instead;
    /// each round takes at least one layer off.
    private func mountAfterDismissal(
        _ firingVC: UIViewController, replacing staleScreen: UIViewController?, retry: PendingPresentation
    ) {
        let top: UIViewController
        switch locateHost() {
        case let .success(located):
            top = located
        case let .failure(miss):
            // The line says if a dismissed owner's `viewDidDisappear` left a sound on.
            retryHostMiss(retry, "firing-present: \(miss.rawValue) after dismissing the previous screen")
            return
        }

        if let alreadyUp = Self.presentedFiringScreen(from: top) {
            if alreadyUp === staleScreen || alreadyUp.isBeingDismissed {
                armRetry(
                    retry,
                    "firing-present: the previous screen is still up after its dismissal — keeping this one pending"
                )
                // Past the limit the request waits for the next activation
                // instead; the line above has already said why.
                if staleSurvivalRetries < Self.staleSurvivalRetryLimit {
                    staleSurvivalRetries += 1
                    attemptParkedPresentationSoon()
                }
            } else if alreadyUp.viewModel.alarm.id == retry.alarmID {
                // By the swap's own test (#855). Stopped or snoozed at
                // `retry`'s count or above answered `retry`, which predates
                // it (`discardPending`'s rule). A lower count is swapped
                // (#808); stale or silent too, at the higher count.
                let shown = PendingPresentation(on: alreadyUp)
                let mismatch = Self.ringMismatch(alreadyUp, for: retry)
                switch mismatch {
                case nil, .stopped?, .snoozed?:
                    let state = mismatch.map { " and \($0.rawValue)" } ?? ""
                    AppLogger.emit(
                        .appDelegate, .default,
                        "firing-present: this alarm's screen is already up\(state) — not stacking another"
                            + " [\(shown.logHandle)]"
                    )
                    clearPending(shownAs: shown)
                    staleSurvivalRetries = 0
                    hostGoneRetries = 0
                case .olderCount?:
                    armRetry(
                        retry, level: .default,
                        "firing-present: this alarm is up at a lower snooze count — swapping it for the right one"
                    )
                case let reason?:
                    let rebuilt = PendingPresentation(
                        alarmID: retry.alarmID, snoozeCount: max(retry.snoozeCount, shown.snoozeCount)
                    )
                    armRetry(
                        rebuilt, level: .default,
                        "firing-present: swapping out the screen of \(shown.logHandle) (\(reason.rawValue))"
                    )
                }
                attemptParkedPresentationSoon()
            } else {
                armRetry(
                    retry,
                    "firing-present: another firing screen went up while the previous one was being dismissed"
                        + " — keeping it pending"
                )
            }
            return
        }

        presentReadingBack(
            firingVC, on: top, request: retry, context: " after dismissing the previous screen", raiseParked: true
        )
    }

    /// Presents `firingVC` on `host` and answers whether it is up, settling the
    /// pending slot either way. Shared by the direct present and the swap's
    /// completion, so the two cannot drift apart again: the direct one kept
    /// answering without a read-back after the completion got one (#833).
    ///
    /// UIKit declines a presentation it cannot perform by doing nothing. Read
    /// back from the screen, as `StatisticsViewController.showLoadErrorAlert`
    /// does (#752/#789): UIKit wires `presentingViewController` inside
    /// `present`, before any completion, so the answer is there on the next
    /// line. A refusal is kept pending rather than given up, like a missing
    /// host after a swap: it is about this moment's hierarchy, and the next
    /// activation asks again. The audio is left alone for the same reason.
    /// A host in a transition (being presented or dismissed, the refusal a
    /// foreground app meets) is asked again when that ends (#875), since in
    /// the foreground no activation comes. Other refusals wait for it.
    ///
    /// Up: `request`'s pending record goes (by `clearPending(shownAs:)`'s
    /// rules, not only on an exact match — #808). What is left in the queue is
    /// re-attempted on the next main-queue turn when it holds this alarm at a
    /// higher count anywhere, not only at its head (#875), or when
    /// `raiseParked` says the queue is newer than this screen. That holds for
    /// the swap, whose completion runs after a request parked during its
    /// dismissal. It does not for the direct path: nothing was mid-swap, so
    /// the queue holds alarms older than the one that just went up, and
    /// raising one would swap the fresh screen out — its sound stopped on the
    /// way down — for an older one: oldest wins, against the arrival order
    /// the flush keeps. With no record of this alarm left, those records wait
    /// for the next activation. With one, the flush the activation would run
    /// runs now, in the same order, and ends on this alarm's higher count.
    ///
    /// `context` is spliced into the refusal line to say which path declined.
    @discardableResult
    private func presentReadingBack(
        _ firingVC: UIViewController, on host: UIViewController, request: PendingPresentation,
        context: String, raiseParked: Bool
    ) -> Bool {
        host.present(firingVC, animated: false)
        guard firingVC.presentingViewController != nil else {
            let reason = AppDelegate.presentationRefusalReason(presenter: host)
                ?? "\(type(of: host)) did not put it up"
            let retry = retryAfterTransition(of: host) ? "; retrying once its transition ends" : ""
            armRetry(request, "firing-present: \(reason)\(context) — keeping it pending\(retry)")
            return false
        }
        clearPending(shownAs: request)
        staleSurvivalRetries = 0
        hostGoneRetries = 0
        if raiseParked {
            // Raised with records still queued behind it, as the flush raises
            // one: the next swaps it out, and that loss is an `.error` (#875).
            raisedFromQueue = pendingQueue.isEmpty ? nil : request
            attemptParkedPresentationSoon()
        } else {
            runQueueSoonForHigherRecord(of: request.alarmID)
        }
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
    /// present on" states was hit, so a miss line names it instead of blaming
    /// the scene for all three. Reached through ``locateHost``.
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

    /// Returns the currently-presented `AlarmFiringViewController` anywhere up
    /// the presentation chain rooted at `topVC`, if one is on screen.
    /// Internal only so `AlarmFiringPresenter+Queue.swift` can reach it (#883).
    static func presentedFiringScreen(from topVC: UIViewController) -> AlarmFiringViewController? {
        var vc: UIViewController? = topVC
        while let current = vc {
            if let firing = current as? AlarmFiringViewController { return firing }
            vc = current.presentingViewController
        }
        return nil
    }
}
