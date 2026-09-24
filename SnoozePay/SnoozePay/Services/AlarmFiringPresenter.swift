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
    /// a swap lands, and on the next turn after a host miss (#875), so the
    /// firing screen survives both a warm-foreground race and a cold start (#382).
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
    private var pendingQueue: [QueuedPresentation] = []

    /// A record and when it was first parked at its count, for the expiry.
    private struct QueuedPresentation {
        let request: PendingPresentation
        let parkedAt: Date
    }

    /// The next record the flush mounts: the oldest one.
    var pendingPresentation: PendingPresentation? { pendingQueue.first?.request }

    /// Every deferred record, oldest first.
    var pendingPresentations: [PendingPresentation] { pendingQueue.map(\.request) }

    /// Which alarm is deferred, for the call sites that only ask that.
    var pendingAlarmID: UUID? { pendingPresentation?.alarmID }

    /// How long a record may wait (#858). Past this the firing it stood for is
    /// over, and raising it would bill a snooze on a ring nobody hears. The
    /// same bound the swap puts on a ring with its own sound.
    static let pendingRecordLifetime: TimeInterval = currentRingSoundingLimit

    /// The clock the expiry reads. A seam so a test can age a record.
    var now: () -> Date = { Date() }

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
    private var hostGoneRetries = 0

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
    /// reset to AlarmKit's 0 (#835). A request that only joins the queue says
    /// nothing; one that yields to a record does.
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
    ///
    /// One record per call, oldest first. Once it lands, the rest follow on
    /// the next main-queue turn: each arrived after it, so each is newer than
    /// the screen that just went up. A record past `pendingRecordLifetime`
    /// is dropped first, with a line (#858).
    private func attemptPendingPresentation() {
        dropExpiredPending()
        guard let pending = pendingPresentation else {
            // The flush is over: no record is left to swap a raised screen out.
            raisedFromQueue = nil
            return
        }
        guard isRootReady() else {
            AppLogger.appDelegate.notice(
                "firing-present: launch root not ready — deferring \(pending.logHandle, privacy: .public)"
            )
            raisedFromQueue = nil
            return
        }
        guard mount(pending.alarmID, pending.snoozeCount) else {
            raisedFromQueue = nil
            return
        }
        pendingQueue.removeAll { $0.request == pending }
        raisedFromQueue = pendingQueue.isEmpty ? nil : pending
        attemptParkedPresentationSoon()
    }

    /// The record this flush, or a swap's completion, raised while more were
    /// queued. The next record swaps its screen out, and that loss is an
    /// `.error` (#858 review, #875).
    private var raisedFromQueue: PendingPresentation?

    private func isExpired(_ queued: QueuedPresentation, at date: Date) -> Bool {
        date.timeIntervalSince(queued.parkedAt) > Self.pendingRecordLifetime
    }

    /// Drops every expired record. Its alarm has no screen coming, so the
    /// sound it owns stops too, by the rule a miss follows (#858 review).
    /// Unless that alarm's screen is up: the sound is then that screen's
    /// ring, a later one than the record stood for, and stopping it left the
    /// screen silent with nothing to restart it.
    private func dropExpiredPending() {
        let current = now()
        let expired = pendingQueue.filter { isExpired($0, at: current) }
        guard !expired.isEmpty else { return }
        pendingQueue.removeAll { isExpired($0, at: current) }
        let limit = Int(Self.pendingRecordLifetime / 60)
        for queued in expired {
            let waited = Int(current.timeIntervalSince(queued.parkedAt) / 60)
            let miss = "dropped after \(waited) min pending, past the \(limit) min limit"
            let alarmID = queued.request.alarmID
            guard AudioService.shared.currentAlarmID == alarmID, isFiringScreenUp(for: alarmID) else {
                stopAudio(ifOwnedBy: queued.request, miss)
                continue
            }
            AppLogger.emit(
                .appDelegate, .error,
                "firing-present: \(miss) [\(queued.request.logHandle)] — its screen is up, leaving it the audio"
            )
        }
    }

    /// Whether `alarmID`'s firing screen is up, by the same walk `present`
    /// makes.
    private func isFiringScreenUp(for alarmID: UUID) -> Bool {
        guard case let .success(top) = locateHost() else { return false }
        return Self.presentedFiringScreen(from: top)?.viewModel.alarm.id == alarmID
    }

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

    /// Ends a miss in `present(alarmID:snoozeCount:)`: stops the sound only
    /// when the missing alarm owns it (#859), the gate `AppDelegate` put on its
    /// own miss in #854. That sound has no screen coming that could stop it.
    /// Another alarm's sound belongs to that alarm's screen, still up and
    /// ringing: a pending slot flushed for a deleted alarm used to silence it
    /// with no dismiss, and its banner went on claiming the last state.
    ///
    /// One line carries the miss, the owner and the decision, with the 8-digit
    /// handles `logHandle` uses on both sides, so a release log can tell the
    /// two alarms apart.
    ///
    /// The rule for every miss (#875): a miss that ends the alarm's record —
    /// not found, fetch failed, expired — comes here, since that alarm has no
    /// screen coming. A miss that keeps the record pending (no host, before
    /// or after a swap; UIKit declining; the root not ready; a stale screen
    /// still up) leaves the audio alone: its screen comes at the next retry or
    /// activation, and restarts the sound only when `!usesAlarmKit`
    /// (`AlarmFiringViewController.viewDidLoad`). `present` has the reasons.
    private func stopAudio(ifOwnedBy missing: PendingPresentation, _ miss: String) {
        // Check and stop in one step (#878), then log what was decided.
        let (stopped, owner) = AudioService.shared.stopAlarmSound(ifOwnedBy: missing.alarmID)
        let ownerHandle = owner.map { String($0.uuidString.prefix(8)) } ?? "nobody"
        let decision = stopped ? "stopping the audio it owns" : "leaving the audio of \(ownerHandle) alone"
        AppLogger.emit(.appDelegate, .error, "firing-present: \(miss) [\(missing.logHandle)] — \(decision)")
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

    /// Runs the queue on the next turn when `alarmID` has a record anywhere in
    /// it, not only at its head. Called right after `clearPending(shownAs:)`,
    /// where the only one it can have left is a later ring: this alarm at a
    /// higher count.
    ///
    /// By the head alone (#875), such a record behind another alarm's waited
    /// for the next activation, and the screen stayed on the lower count's
    /// price. The retry itself still goes oldest first: the other alarm's
    /// record goes up before it, and this alarm's, the newer, stays on screen.
    ///
    /// That order swaps a fresh screen out for an older alarm, which the
    /// direct path otherwise never does, so it gets one line saying why. None
    /// when this alarm's record is the head: the swap line that follows names
    /// "a lower snooze count" and explains itself.
    private func runQueueSoonForHigherRecord(of alarmID: UUID) {
        guard let record = pendingQueue.first(where: { $0.request.alarmID == alarmID })?.request else { return }
        if let head = pendingPresentation, head.alarmID != alarmID {
            AppLogger.emit(
                .appDelegate, .default,
                "firing-present: [\(record.logHandle)] waits behind [\(head.logHandle)] — running the queue now"
            )
        }
        attemptParkedPresentationSoon()
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
            armRetry(request, "firing-present: \(reason)\(context) — keeping it pending")
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

    /// Re-attempts a request the swap parked — another alarm that arrived
    /// while the dismissal was outstanding — once this swap's screen is up.
    ///
    /// Waiting for "the next activation" was no retry at all: while the app
    /// stays foreground `sceneDidBecomeActive` does not fire again, and on a
    /// background scene the activation can land before this completion and
    /// be parked itself. On the next main-queue turn, not inline, so the
    /// follow-up swap never dismisses a screen that is still being presented.
    /// Called from the branches where a screen is up (on the direct path and
    /// for a ringing screen the swap keeps, only while this alarm has a record
    /// at a higher count, #833/#835/#875), and from two failure branches,
    /// each counting its calls against its own limit so it cannot spin: a
    /// stale screen that outlived its dismissal (`staleSurvivalRetryLimit`)
    /// and a host miss, in `present` or after the dismissal
    /// (`hostGoneRetryLimit`, #875). The other failure branches leave the
    /// retry to the activation.
    private func attemptParkedPresentationSoon() {
        guard pendingPresentation != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.attemptPendingPresentation()
        }
    }

    /// A host miss, in `present` or after a swap's dismissal: keeps the record
    /// and the audio (`stopAudio(ifOwnedBy:_:)`'s rule) and re-arms on the next
    /// turn, `hostGoneRetryLimit` times since the last screen went up (#875).
    private func retryHostMiss(_ request: PendingPresentation, _ miss: String) {
        let retrying = hostGoneRetries < Self.hostGoneRetryLimit
        armRetry(
            request, "\(miss) — keeping it pending; \(Self.inAppSoundNote); "
                + (retrying ? "retrying on the next turn" : "waiting for the next activation")
        )
        guard retrying else { return }
        hostGoneRetries += 1
        attemptParkedPresentationSoon()
    }

    /// Whose in-app sound is on, for the line of a miss that leaves the audio
    /// alone: the owner's 8-hex handle, by `AppDelegate.logHandle`.
    private static var inAppSoundNote: String {
        AudioService.shared.state == .stopped ? "no in-app sound is on"
            : "the in-app sound of \(AppDelegate.logHandle(AudioService.shared.soundingAlarmID)) is on"
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
    ///
    /// Unless that record has expired: yesterday's `(A, 3)` is not a later
    /// ring of today's `(A, 0)`, and left behind, its drop on the next flush
    /// stopped the sound of the screen that had just gone up (#858 review).
    private func clearPending(shownAs shown: PendingPresentation) {
        let current = now()
        pendingQueue.removeAll {
            $0.request.alarmID == shown.alarmID
                && ($0.request.snoozeCount <= shown.snoozeCount || isExpired($0, at: current))
        }
    }

    /// Offers `retry` to the pending queue and writes `line`, naming the alarm,
    /// where the suite can read it.
    ///
    /// The queue holds one record per alarm, so what it keeps is a rule:
    ///
    ///   * Another alarm's record stays where it is, and `retry` joins the
    ///     queue after it (#858). A slot replaced it, newest wins, and lost it.
    ///   * This alarm's record at a HIGHER count stays, and the line says so.
    ///     Replacing it prices the next snooze from an earlier step: the rule
    ///     `clearPending(shownAs:)` follows for the same reason (#807/#808).
    ///     The line keeps the caller's level: nothing is lost, but the alarm is
    ///     still not up.
    ///   * At a lower count, `retry` takes its place in the queue. At the same
    ///     count the record is kept as it is, with its `parkedAt`: a retry does
    ///     not restart the expiry.
    ///   * An expired record of this alarm counts as absent: `retry` replaces
    ///     it at the back, with a fresh `parkedAt`. Merged into it, a request
    ///     hours later was dropped with it on the flush (#858 review).
    ///
    /// Compared by id AND count: by id alone, `(A, 0)` silently replaced a
    /// parked `(A, 3)`. `line == nil` is AlarmKit's request, which is not a
    /// failure: it writes only when the rule kept or replaced a record.
    private func armRetry(_ retry: PendingPresentation, level: OSLogType = .error, _ line: String?) {
        let current = now()
        var index = pendingQueue.firstIndex { $0.request.alarmID == retry.alarmID }
        var expired: PendingPresentation?
        if let stale = index, isExpired(pendingQueue[stale], at: current) {
            expired = pendingQueue.remove(at: stale).request
            index = nil
        }
        let parked = index.map { pendingQueue[$0].request }
        let outranked = parked.map { $0.snoozeCount > retry.snoozeCount } ?? false
        let queued = QueuedPresentation(request: retry, parkedAt: current)
        if let index, let parked, parked.snoozeCount < retry.snoozeCount {
            pendingQueue[index] = queued
        } else if index == nil {
            pendingQueue.append(queued)
        }

        let outcome: String
        if outranked, let parked {
            outcome = "; the pending \(parked.logHandle) outranks it and stays"
        } else if let expired {
            outcome = "; it replaces the expired \(expired.logHandle)"
        } else if line != nil {
            outcome = ""
        } else {
            return
        }
        AppLogger.emit(.appDelegate, level, "\(line ?? "firing-present: requested") [\(retry.logHandle)]\(outcome)")
    }

    /// Drops the record the user just stopped on screen (#835). A record for
    /// that alarm parked while the screen was up (a present UIKit deferred, a
    /// second trigger source) would otherwise raise a firing screen on the
    /// next activation for an alarm the user already stopped. Only one the
    /// stopped screen covers: another alarm's record, or this alarm's at a
    /// higher count than the screen (a later ring), stays. Called from the
    /// screen's `onUserStop`.
    private func discardPending(stopped: PendingPresentation) {
        guard let pending = pendingQueue.first(where: { $0.request.alarmID == stopped.alarmID })?.request,
              pending.snoozeCount <= stopped.snoozeCount else { return }
        AppLogger.emit(
            .appDelegate, .default, "firing-present: stopped on its screen — dropping [\(pending.logHandle)]"
        )
        pendingQueue.removeAll { $0.request == pending }
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
