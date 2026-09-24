import UIKit
import os

// MARK: - Pending queue
//
// Extracted from `AlarmFiringPresenter.swift` (#883) so the host file stays under
// SwiftLint's `file_length` cap: the records the presenter could not mount yet,
// their expiry, and the retries that raise them. The move was verbatim apart from
// access modifiers; the stored state stays in the class body.

extension AlarmFiringPresenter {

    /// A record and when it was first parked at its count, for the expiry.
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    struct QueuedPresentation {
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
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func stopAudio(ifOwnedBy missing: PendingPresentation, _ miss: String) {
        // Check and stop in one step (#878), then log what was decided.
        let (stopped, owner) = AudioService.shared.stopAlarmSound(ifOwnedBy: missing.alarmID)
        let ownerHandle = owner.map { String($0.uuidString.prefix(8)) } ?? "nobody"
        let decision = stopped ? "stopping the audio it owns" : "leaving the audio of \(ownerHandle) alone"
        AppLogger.emit(.appDelegate, .error, "firing-present: \(miss) [\(missing.logHandle)] — \(decision)")
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
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func runQueueSoonForHigherRecord(of alarmID: UUID) {
        guard let record = pendingQueue.first(where: { $0.request.alarmID == alarmID })?.request else { return }
        if let head = pendingPresentation, head.alarmID != alarmID {
            AppLogger.emit(
                .appDelegate, .default,
                "firing-present: [\(record.logHandle)] waits behind [\(head.logHandle)] — running the queue now"
            )
        }
        attemptParkedPresentationSoon()
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
    /// (`hostGoneRetryLimit`, #875). And from the end of a UIKit transition
    /// that refused a present or held a swap, one turn after it, counted
    /// against `transitionRetryLimit` (#875): `retryAfterTransition(of:)`.
    /// The other failure branches leave the retry to the activation.
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func attemptParkedPresentationSoon() {
        guard pendingPresentation != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.attemptPendingPresentation()
        }
    }

    /// Whether a present refused by `controller`'s UIKit transition, or a swap
    /// held by it, is retried at that transition's end (#875, items 3 and 6).
    /// `nil`: the controller is in no transition. Otherwise `true` while
    /// `transitionRetryLimit` is not spent since the last screen went up.
    /// Asked before the record is parked, so its line says what follows.
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func transitionRetry(for controller: UIViewController) -> Bool? {
        guard isInTransition(controller) else { return nil }
        return transitionRetries < Self.transitionRetryLimit
    }

    /// The tail of the line `transitionRetry(for:)`'s answer writes.
    static func transitionRetryNote(retrying: Bool) -> String {
        retrying ? "retrying once its transition ends" : "waiting for the next activation"
    }

    /// Schedules the queue for the end of `controller`'s UIKit transition,
    /// after `transitionRetry(for:)` said yes and the record is parked: UIKit
    /// may run the completion inside the call.
    ///
    /// The completion only hops a turn. Running the queue inside it, a host
    /// UIKit still reports in the transition refuses again and schedules the
    /// next retry from within this one, with no bound when the completion is
    /// synchronous. Each call counts against `transitionRetryLimit`.
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func retryAfterTransition(of controller: UIViewController) {
        transitionRetries += 1
        let scheduled = whenTransitionEnds(controller) { [weak self] in
            self?.attemptParkedPresentationSoon()
        }
        // The coordinator is gone since `transitionRetry(for:)` saw it: the
        // transition is over, so the next turn is its end.
        if !scheduled { attemptParkedPresentationSoon() }
    }

    /// The production `whenTransitionEnds` on `animate`'s NO (#886): `body` also goes to the next
    /// turn, never inside the call. Static so a test reaches it without a live transition.
    static func runSoonUnlessQueued(_ animationQueued: Bool, _ body: @escaping () -> Void) {
        if !animationQueued { DispatchQueue.main.async(execute: body) }
    }

    /// A host miss, in `present` or after a swap's dismissal: keeps the record
    /// and the audio (`stopAudio(ifOwnedBy:_:)`'s rule) and re-arms on the next
    /// turn, `hostGoneRetryLimit` times since the last screen went up (#875).
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func retryHostMiss(_ request: PendingPresentation, _ miss: String) {
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
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func clearPending(shownAs shown: PendingPresentation) {
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
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func armRetry(_ retry: PendingPresentation, level: OSLogType = .error, _ line: String?) {
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
    /// Internal only so `AlarmFiringPresenter.swift` can reach it (#883).
    func discardPending(stopped: PendingPresentation) {
        guard let pending = pendingQueue.first(where: { $0.request.alarmID == stopped.alarmID })?.request,
              pending.snoozeCount <= stopped.snoozeCount else { return }
        AppLogger.emit(
            .appDelegate, .default, "firing-present: stopped on its screen — dropping [\(pending.logHandle)]"
        )
        pendingQueue.removeAll { $0.request == pending }
    }
}

extension AlarmFiringPresenter.PendingPresentation {
    /// The record `screen` stands for: its alarm at the count it shows.
    @MainActor
    init(on screen: AlarmFiringViewController) {
        self.init(alarmID: screen.viewModel.alarm.id, snoozeCount: screen.viewModel.snoozeCount)
    }
}
