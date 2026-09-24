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
    /// the launch splash (#834). And by a swap, before its dismissal starts,
    /// unless another alarm holds the slot (#835). What a write may replace
    /// is `armRetry`'s rule. Flushed by
    /// `flushPendingPresentation()` once the scene becomes active, and right
    /// after a swap lands, so the firing
    /// screen survives both a warm-foreground race and a cold start (#382).
    ///
    /// The snooze count travels with the id because the retry rebuilds the
    /// screen from this record alone, and the penalty is priced from it
    /// (`penalty(forSnoozeCount: snoozeCount + 1)`). Held as one value rather
    /// than two optionals so the pair cannot come apart: the retry used to
    /// mount with `0`, which put a deferred third snooze back on the first
    /// step's price (#808).
    ///
    /// `private(set)` so tests can assert the deferred screen without poking
    /// the internals through reflection.
    private(set) var pendingPresentation: PendingPresentation?

    /// Which alarm is deferred, for the call sites that only ask that.
    var pendingAlarmID: UUID? { pendingPresentation?.alarmID }

    /// Everything the retry needs to rebuild the firing screen it could not
    /// mount the first time.
    struct PendingPresentation: Equatable {
        let alarmID: UUID
        let snoozeCount: Int

        /// Names the request in a presenter line (#835): the first eight hex
        /// digits of the id, and the count. `AppLogger.emit` writes `.public`,
        /// and the whole id is an identifier the logger keeps private. Eight
        /// digits are enough to tell apart the alarms in one incident and to
        /// match one alarm's lines to each other, which #798 could not do.
        var logHandle: String { "alarm \(alarmID.uuidString.prefix(8)) at snooze \(snoozeCount)" }
    }

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
    /// only what it presented and leaves it standing (#807).
    var dismissStaleScreen: (UIViewController, @escaping () -> Void) -> Void = { staleScreen, completion in
        (staleScreen.presentingViewController ?? staleScreen).dismiss(animated: false, completion: completion)
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

    /// The request whose screen the swap on `screenBeingDismissed` mounts in
    /// its completion. A request taking the slot from it while that dismissal
    /// is in flight gives up its retry, not its screen, and `armRetry` says so
    /// instead of calling it dropped (#835 review).
    private var requestBeingSwappedIn: PendingPresentation?

    /// Re-attempts spent on a stale screen that outlived its own dismissal,
    /// since the last screen that went up. Bounds that retry: nothing in the
    /// hierarchy guarantees each dismissal removes a layer, and a completion
    /// that removes nothing would otherwise re-swap on every main-queue turn —
    /// an `.error` line and a fresh screen each time, all night (#807 review).
    private var staleSurvivalRetries = 0

    /// Enough for a stale screen with one layer on it (dismissal takes the
    /// layer, the retry takes the screen) plus one spare.
    static let staleSurvivalRetryLimit = 2

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

    // MARK: - Pending-present entry point (#382)

    /// Request the firing screen for `alarmID` from a context that may run
    /// before any foreground window exists — the AlarmKit alert buttons
    /// (`AlarmKitActionRouter`, whose intents set `openAppWhenRun`) and the
    /// alerting observer. Records the id and snooze count as pending and
    /// attempts an immediate present; if no scene/root is attached yet (cold
    /// launch, or the foreground transition hasn't completed) the present is a
    /// no-op and the record is flushed later by `flushPendingPresentation()` from
    /// `SceneDelegate.sceneDidBecomeActive`. This is what makes tapping an
    /// AlarmKit alarm actually open the app *and* land on our screen (#382) —
    /// presenting directly in the intent's `perform()` lost the race and the
    /// screen never appeared.
    ///
    /// Recorded through `armRetry`'s rule, not written over the slot: a
    /// record from the notification path parked since #834 was overwritten
    /// with no line at all, and one for this alarm at a higher count was
    /// reset to AlarmKit's 0 (#835). A request that only fills the slot says
    /// nothing; one that drops or yields to a record does.
    func requestPresentation(alarmID: UUID, snoozeCount: Int = 0) {
        armRetry(PendingPresentation(alarmID: alarmID, snoozeCount: snoozeCount), level: .default, nil)
        attemptPendingPresentation()
    }

    /// Mount any deferred firing screen now that the scene is active. Called
    /// from `SceneDelegate.sceneDidBecomeActive` (and after the splash → root
    /// transition completes). Clears the pending record only once the present
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
    /// after a successful present (#382). The snooze count comes from the
    /// pending record, never a default: a retry is the same screen, not a
    /// fresh one (#808).
    private func attemptPendingPresentation() {
        guard let pending = pendingPresentation else { return }
        guard isRootReady() else {
            AppLogger.appDelegate.notice(
                "firing-present: launch root not ready — deferring \(pending.logHandle, privacy: .public)"
            )
            return
        }
        if mount(pending.alarmID, pending.snoozeCount) {
            pendingPresentation = nil
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
    /// `false` when it was not up by the time this returned — the signal the
    /// pending-present retry (#382) keys off. See `present(alarm:snoozeCount:)`
    /// for the two states behind that `false`.
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
    /// parked for the next activation (#835), except when another alarm held
    /// the slot: that record is kept, and this request then waits on the
    /// completion alone.
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
            // The reason is the locator's: "no window scene" was true of only
            // one of the three states this returns on, and the loudest one —
            // audio stopped, screen never raised — is the state where a scene
            // and windows exist but none of them can host a presentation.
            //
            // The retry is armed here rather than left to the caller: the
            // pending path keeps its record on `false`, but the notification
            // path (`AppDelegate.presentAlarmFiringScreen`) discards the
            // answer, so a miss there lost the alarm — no sound, no screen,
            // nothing to raise it again (#834). The audio still stops: nothing
            // on screen could silence it until the retry lands, and the screen
            // the retry raises starts it again itself.
            //
            // Through `armRetry`, which writes with `AppLogger.emit`, because
            // this line IS the outcome and #795 found it read by no test.
            // `miss.rawValue` is a fixed sentence, so `emit`'s implicit
            // `.public` is the marker it already carried.
            armRetry(request, "firing-present: \(miss.rawValue) — stopping audio, keeping it pending")
            AudioService.shared.stopAlarmSound()
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
            parkBeforeSwap(request, replacing: presentedFiring, because: mismatch)
            requestBeingSwappedIn = request
            // Set before the call so a completion UIKit runs synchronously
            // clears it rather than finding nothing to clear. Leaving a stale
            // marker behind is harmless now that the guard above also needs
            // `isBeingDismissed`, but the marker then names a swap that is over.
            screenBeingDismissed = presentedFiring
            dismissStaleScreen(presentedFiring) { [weak self, weak presentedFiring] in
                guard let self else { return }
                if self.screenBeingDismissed === presentedFiring {
                    self.screenBeingDismissed = nil
                    self.requestBeingSwappedIn = nil
                }
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

    /// The swap's own park, before its dismissal starts, so a completion
    /// UIKit never runs leaves the request waiting for the next activation
    /// rather than neither shown nor parked (#835). The completion clears it.
    /// The line names the screen going down: a ringing screen of another
    /// alarm goes silent in its `viewDidDisappear`, and this line is all that
    /// says why.
    ///
    /// Not over another alarm's record: parking would drop it, while left
    /// alone it is raised once this swap lands (`raiseParked`), as on main.
    /// The cost is this request on the notification path when UIKit never
    /// completes the dismissal (#835 follow-up).
    private func parkBeforeSwap(
        _ request: PendingPresentation, replacing screen: AlarmFiringViewController, because mismatch: RingMismatch
    ) {
        let line = "firing-present: swapping out the screen of \(PendingPresentation(on: screen).logHandle)"
            + " (\(mismatch.rawValue))"
        guard let parked = pendingPresentation, parked.alarmID != request.alarmID else {
            armRetry(request, level: .default, line)
            return
        }
        AppLogger.emit(
            .appDelegate, .default, "\(line) [\(request.logHandle)]; not parked over the pending \(parked.logHandle)"
        )
    }

    /// How recently the ring on an AlarmKit screen must have started for a
    /// request to count as that same ring (`ringMismatch`). Measured from
    /// `AlarmFiringViewModel.lastRingStartedAt`, the re-ring after the last
    /// snooze or the mount before any: from the mount alone, one snooze of 11
    /// to 15 minutes put a second trigger for the ring outside it (#855). The
    /// requests it absorbs arrive within seconds to a minute of the ring. Ten
    /// minutes covers those with room, and stays far below the day between
    /// two mornings: a screen left up since yesterday must be swapped (#835
    /// review).
    static let currentFiringWindow: TimeInterval = 10 * 60

    /// Why a screen of `request`'s alarm is not the ring the request is for.
    /// Printed in the swap lines next to the screen's handle.
    enum RingMismatch: String {
        case otherAlarm = "another alarm"
        case olderCount = "a lower snooze count"
        case dismissing = "being dismissed"
        case stopped = "stopped by the user"
        case snoozed = "snoozed"
        case outsideWindow = "rang too long ago"
        case silent = "its sound is not on"
    }

    /// `nil` when `screen` is `request`'s alarm at the request's count or
    /// above, still ringing its current ring, so the request is the screen
    /// already there. The one test both the swap (`present(alarm:)`) and its
    /// completion (`mountAfterDismissal`) apply (#855).
    ///
    /// Ringing: this alarm owns `AudioService` in any state but `.stopped`
    /// (a swap would kill a vibration-only ring), read once as a pair. That
    /// proves the ring with no window, so a long ring keeps its fade-in.
    /// Without it only AlarmKit, whose sound is the system's, can be ringing,
    /// and only inside `currentFiringWindow`: the flags alone prove nothing.
    private static func ringMismatch(
        _ screen: AlarmFiringViewController, for request: PendingPresentation
    ) -> RingMismatch? {
        let model = screen.viewModel
        if model.alarm.id != request.alarmID { return .otherAlarm }
        if model.snoozeCount < request.snoozeCount { return .olderCount }
        if screen.isBeingDismissed { return .dismissing }
        if screen.isStoppedByUser { return .stopped }
        if screen.isSnoozedStateActive { return .snoozed }
        if AudioService.shared.soundingAlarmID == model.alarm.id { return nil }
        if !model.usesAlarmKit { return .silent }
        return Date().timeIntervalSince(model.lastRingStartedAt) <= currentFiringWindow ? nil : .outsideWindow
    }

    /// Settles the request on `screen`, the ringing screen the swap would
    /// otherwise take down: swapping rebuilt it and stopped its sound on the
    /// way down (#835).
    private func settleOnRingingScreen(_ screen: AlarmFiringViewController) {
        let shown = PendingPresentation(on: screen)
        AppLogger.emit(
            .appDelegate, .default,
            "firing-present: this alarm's screen is up and ringing — not swapping it [\(shown.logHandle)]"
        )
        clearPending(shownAs: shown)
        if pendingAlarmID == shown.alarmID { attemptParkedPresentationSoon() }
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
            // Not stopped here, unlike the miss in `present`, but a dismissed
            // screen that owned the sound stopped it in `viewDidDisappear`:
            // the line says whether any is left until the retry lands.
            let audio = AudioService.shared.state == .stopped ? "no in-app sound is on" : "the in-app sound is on"
            armRetry(
                retry,
                "firing-present: \(miss.rawValue) after dismissing the previous screen — keeping it pending; \(audio)"
            )
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
    ///
    /// Up: `request`'s pending record goes (by `clearPending(shownAs:)`'s
    /// rules, not only on an exact match — #808). What is left in the slot is
    /// re-attempted on the next main-queue turn when it is this alarm at a
    /// higher count, or when `raiseParked` says the slot is newer than this
    /// screen. That holds for the swap, whose completion runs after a request
    /// parked during its dismissal. It does not for the direct path: nothing
    /// was mid-swap, so the slot holds an alarm older than the one that just
    /// went up, and raising it would swap the fresh screen out — its sound
    /// stopped on the way down — for the older one: oldest wins, against
    /// `armRetry`'s newest wins. That record waits for the next activation.
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
            armRetry(request, "firing-present: \(reason)\(context) — keeping it pending")
            return false
        }
        clearPending(shownAs: request)
        staleSurvivalRetries = 0
        if raiseParked || pendingAlarmID == request.alarmID {
            attemptParkedPresentationSoon()
        }
        return true
    }

    /// Re-attempts a request the swap parked — another alarm that arrived
    /// while the dismissal was outstanding — once this swap's screen is up.
    ///
    /// Waiting for "the next activation" was no retry at all: while the app
    /// stays foreground `sceneDidBecomeActive` does not fire again, and on a
    /// background scene the activation can land before this completion and
    /// be parked itself. On the next main-queue turn, not inline, so the
    /// follow-up swap never dismisses a screen that is still being presented.
    /// Called from the branches where a screen is up (on the direct path and
    /// for a ringing screen the swap keeps, only for this alarm at a higher
    /// count, #833/#835), and from the one failure
    /// branch that can still settle on its own — a stale screen that outlived
    /// its dismissal — which counts its calls against
    /// `staleSurvivalRetryLimit`, so it cannot spin. The other failure
    /// branches leave the retry to the activation.
    private func attemptParkedPresentationSoon() {
        guard pendingPresentation != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.attemptPendingPresentation()
        }
    }

    /// Drops the deferral once `shown` — an alarm at a snooze count — is on
    /// screen.
    ///
    /// Only this alarm's: a direct `present(alarm:)` from the notification path
    /// can land while a different alarm sits pending from AlarmKit, and
    /// clearing that one would drop the screen #798 exists to keep. Not only on
    /// an exact match: the same alarm deferred by AlarmKit at count 0 and then
    /// shown at 2 is shown, and keeping `(id, 0)` would re-mount it at 0 on the
    /// next activation — the reset #808 closes (pinned by
    /// `testReentry_forTheAlarmAlreadyPendingAtAnotherCount_clearsIt`). But a
    /// record for this alarm at a HIGHER count than the screen stays: it was
    /// parked while an AlarmKit swap at 0 was in flight, and dropping it leaves
    /// the screen on the first step's price (#807). The follow-up re-attempt
    /// swaps it in.
    private func clearPending(shownAs shown: PendingPresentation) {
        guard let pending = pendingPresentation, pending.alarmID == shown.alarmID else { return }
        if pending.snoozeCount <= shown.snoozeCount {
            pendingPresentation = nil
        }
    }

    /// Offers `retry` to the pending slot and writes `line`, naming the alarm,
    /// where the suite can read it.
    ///
    /// The slot holds one record, so what it keeps is a rule (#835):
    ///
    ///   * Another alarm's record is replaced — newest wins — and the line
    ///     names both alarms at `.error`, whatever `level` the caller asked
    ///     for. A lost retry is not a notice, and it may be a snooze AlarmKit
    ///     already stopped the system alarm for. Unless that record is the one
    ///     an in-flight swap mounts: then only its retry goes, and the line
    ///     says that at the caller's level.
    ///   * This alarm's record at a HIGHER count stays, and the line says so.
    ///     Replacing it prices the next snooze from an earlier step: the rule
    ///     `clearPending(shownAs:)` follows for the same reason (#807/#808).
    ///     The line keeps the caller's level: nothing is lost, but the alarm is
    ///     still not up.
    ///   * Otherwise `retry` takes the slot.
    ///
    /// Compared by id AND count: by id alone, `(A, 0)` silently replaced a
    /// parked `(A, 3)`. `line == nil` is AlarmKit's request, which is not a
    /// failure: it writes only when the rule dropped or kept a record.
    private func armRetry(_ retry: PendingPresentation, level: OSLogType = .error, _ line: String?) {
        let parked = pendingPresentation
        let displaced = parked.map { $0.alarmID != retry.alarmID } ?? false
        let stillSwappingIn = displaced && parked == requestBeingSwappedIn
            && screenBeingDismissed?.isBeingDismissed == true
        let outranked = !displaced && (parked.map { $0.snoozeCount > retry.snoozeCount } ?? false)
        if !outranked { pendingPresentation = retry }

        let outcome: String
        if stillSwappingIn, let parked {
            outcome = "; \(parked.logHandle) leaves the slot but is still being swapped in"
        } else if displaced, let parked {
            outcome = "; another alarm's pending screen is dropped: \(parked.logHandle)"
        } else if outranked, let parked {
            outcome = "; the pending \(parked.logHandle) outranks it and stays"
        } else if line != nil {
            outcome = ""
        } else {
            return
        }
        AppLogger.emit(
            .appDelegate, displaced && !stillSwappingIn ? .error : level,
            "\(line ?? "firing-present: requested") [\(retry.logHandle)]\(outcome)"
        )
    }

    /// Drops the record the user just stopped on screen (#835). A record for
    /// that alarm parked while the screen was up (a present UIKit deferred, a
    /// second trigger source) would otherwise raise a firing screen on the
    /// next activation for an alarm the user already stopped. Only one the
    /// stopped screen covers: another alarm's record, or this alarm's at a
    /// higher count than the screen (a later ring), stays. Called from the
    /// screen's `onUserStop`.
    private func discardPending(stopped: PendingPresentation) {
        guard let pending = pendingPresentation, pending.alarmID == stopped.alarmID,
              pending.snoozeCount <= stopped.snoozeCount else { return }
        AppLogger.emit(
            .appDelegate, .default, "firing-present: stopped on its screen — dropping [\(pending.logHandle)]"
        )
        pendingPresentation = nil
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

    /// Returns the currently-presented `AlarmFiringViewController` anywhere up
    /// the presentation chain rooted at `topVC`, if one is on screen.
    private static func presentedFiringScreen(from topVC: UIViewController) -> AlarmFiringViewController? {
        var vc: UIViewController? = topVC
        while let current = vc {
            if let firing = current as? AlarmFiringViewController { return firing }
            vc = current.presentingViewController
        }
        return nil
    }
}

extension AlarmFiringPresenter.PendingPresentation {
    /// The record `screen` stands for: its alarm at the count it shows.
    @MainActor
    init(on screen: AlarmFiringViewController) {
        self.init(alarmID: screen.viewModel.alarm.id, snoozeCount: screen.viewModel.snoozeCount)
    }
}
