import Foundation
import os

/// Handles the business logic triggered by notification actions on a fired
/// alarm (snooze charge + reschedule). Extracted from AppDelegate so the same
/// flow can be unit-tested without spinning up the UIApplication / notification
/// center machinery.
///
/// AppDelegate is responsible only for routing the raw `UNNotificationResponse`
/// into the right method here; all balance / repository / scheduler wiring
/// lives in this coordinator.
final class AlarmFiringCoordinator {

    static let shared = AlarmFiringCoordinator()

    // MARK: - Outcome

    /// Result of attempting a snooze from a notification action.
    /// Surfaced for tests and AppDelegate so a `.scheduleFailed` can drive a
    /// user-visible local notification — without that surface a `UN.add`
    /// failure here silently swallows the snooze and the user has already
    /// paid the penalty (issue #130, follow-up to #118 / silent-failure-hunter
    /// review of #127).
    enum SnoozeOutcome: Equatable {
        /// Required identifiers (alarmID/snoozeCount) were missing or malformed.
        case invalidPayload
        /// Identifiers were valid but the alarm has been deleted from the repo.
        case alarmNotFound
        /// Balance was insufficient to cover the (possibly progressive) penalty.
        case insufficientFunds
        /// Charge succeeded and a new snooze notification was scheduled.
        case scheduled(newSnoozeCount: Int, charged: Double)
        /// Charge succeeded but the underlying `UNUserNotificationCenter.add`
        /// rejected the snooze trigger (revoked permission, 64-pending-limit,
        /// malformed trigger). The penalty has been **refunded** synchronously
        /// inside the coordinator before this outcome is reported, so the
        /// wallet reflects the unsuccessful snooze. Callers (AppDelegate) MUST
        /// surface a local banner so the user knows the alarm will not re-fire.
        case scheduleFailed(error: AlarmScheduler.SchedulingError)
        /// Charge succeeded, schedule failed, AND the offsetting refund also
        /// failed (typically because the ledger is locked from a corrupt blob,
        /// see #72/#119). Wallet is in a degraded state — money was taken,
        /// alarm will not re-fire, refund did not land. Callers MUST surface
        /// a stronger banner instructing the user to contact support so they
        /// don't silently lose the penalty (silent-failure-hunter HIGH on #132).
        case scheduleFailedAndRefundFailed(error: AlarmScheduler.SchedulingError)
    }

    // MARK: - Dependencies

    private let alarmRepository: AlarmRepository
    private let balanceService: BalanceService
    private let scheduler: AlarmScheduler

    /// Production code MUST use `AlarmFiringCoordinator.shared`. Direct
    /// construction is intended for tests so they can inject mocks /
    /// isolated services without polluting the real singletons.
    #if DEBUG
    init(
        alarmRepository: AlarmRepository = .shared,
        balanceService: BalanceService = .shared,
        scheduler: AlarmScheduler = .shared
    ) {
        self.alarmRepository = alarmRepository
        self.balanceService = balanceService
        self.scheduler = scheduler
    }
    #else
    private init(
        alarmRepository: AlarmRepository = .shared,
        balanceService: BalanceService = .shared,
        scheduler: AlarmScheduler = .shared
    ) {
        self.alarmRepository = alarmRepository
        self.balanceService = balanceService
        self.scheduler = scheduler
    }
    #endif

    // MARK: - Snooze

    /// Resolves the alarm + snoozeCount from a notification's userInfo dict,
    /// charges the appropriate (possibly progressive) penalty, and schedules
    /// the next snooze notification. The outcome is delivered via `completion`
    /// because `scheduleSnooze` is asynchronous — callers (AppDelegate, tests)
    /// must wait for the scheduler to confirm registration before they can
    /// distinguish `.scheduled` from `.scheduleFailed` (issue #130).
    ///
    /// On `.scheduleFailed` the penalty is refunded via
    /// `BalanceService.topUp` so the user is not billed for a snooze that
    /// will never re-fire. The refund posts an offsetting ledger entry —
    /// transaction history therefore shows both the charge and the refund,
    /// which is the consistent representation for stats/auditing (mirrors the
    /// rollback pattern from StoreKitService dedup-mark in #72).
    ///
    /// Synchronous early-exit branches (invalid payload, alarm missing,
    /// insufficient funds) call `completion` inline before returning so the
    /// caller sees a single resolution per invocation.
    func handleSnooze(
        userInfo: [AnyHashable: Any],
        completion: ((SnoozeOutcome) -> Void)? = nil
    ) {
        guard let payload = AlarmNotificationPayload(userInfo: userInfo) else {
            AppLogger.coordinator.error("snooze: invalid payload \(userInfo, privacy: .private(mask: .hash))")
            completion?(.invalidPayload)
            return
        }

        let alarm: Alarm?
        do {
            // Use the checked variant so a corrupt store surfaces in logs
            // rather than collapsing into the "alarmNotFound" outcome —
            // otherwise a transient decode glitch silently turns into
            // "snooze didn't work" with no diagnostic trail (issue #117).
            alarm = try alarmRepository.fetchChecked(id: payload.alarmID)
        } catch {
            let errorDesc = String(describing: error)
            AppLogger.coordinator.error(
                "snooze: fetch failed for \(payload.alarmID, privacy: .private): \(errorDesc, privacy: .public)"
            )
            completion?(.alarmNotFound)
            return
        }
        guard let alarm else {
            AppLogger.coordinator.error("snooze: alarm \(payload.alarmID, privacy: .private) not in repository")
            completion?(.alarmNotFound)
            return
        }

        let newCount = payload.snoozeCount + 1
        let penalty = alarm.penalty(forSnoozeCount: newCount)

        let charged = balanceService.charge(amount: penalty, alarmID: payload.alarmID)
        guard charged else {
            let alarmID = payload.alarmID
            AppLogger.coordinator.notice(
                "snooze: insufficient funds alarm=\(alarmID, privacy: .private) penalty=\(penalty, privacy: .public)"
            )
            completion?(.insufficientFunds)
            return
        }

        // Cancel THIS firing's lock-screen fallback bursts before rescheduling
        // (#19 QA): the primary alarm's `_burstN` follow-ups are still pending at
        // +30/60/90s and would re-ring on top of the snooze the user just chose.
        // Burst-only — the alarm's primary repeating triggers stay armed so a
        // weekly alarm still fires on its next day.
        scheduler.cancelFallbackBursts(payload.alarmID)

        scheduler.scheduleSnooze(for: alarm, snoozeCount: newCount) { [weak self] result in
            self?.handleScheduleResult(
                result,
                alarmID: payload.alarmID,
                newCount: newCount,
                penalty: penalty,
                completion: completion
            )
        }
    }

    /// Resolves the async scheduler result into a `SnoozeOutcome`. On failure
    /// the penalty is refunded via `BalanceService.topUp` so the user is not
    /// billed for a snooze that won't re-fire — extracted from `handleSnooze`
    /// to keep the entry-point readable and to give the refund logic its own
    /// log seam.
    private func handleScheduleResult(
        _ result: Result<Void, AlarmScheduler.SchedulingError>,
        alarmID: UUID,
        newCount: Int,
        penalty: Double,
        completion: ((SnoozeOutcome) -> Void)?
    ) {
        switch result {
        case .success:
            AppLogger.coordinator.info(
                "snooze: scheduled #\(newCount, privacy: .public) alarm=\(alarmID, privacy: .private)"
            )
            completion?(.scheduled(newSnoozeCount: newCount, charged: penalty))
        case .failure(let error):
            // Refund the penalty so the user isn't billed for a snooze that
            // will never re-fire. `topUp` records an offsetting ledger entry
            // (rather than mutating storage directly) so transaction history
            // shows both the charge and the refund — stats stay auditable.
            let refunded = balanceService.topUp(amount: penalty)
            let desc = error.errorDescription ?? error.localizedDescription
            if refunded {
                AppLogger.coordinator.error(
                    """
                    snooze: schedule failed alarm=\(alarmID, privacy: .private) \
                    refunded=\(penalty, privacy: .public) reason=\(desc, privacy: .public)
                    """
                )
                completion?(.scheduleFailed(error: error))
            } else {
                // Refund itself failed — wallet is in a degraded state
                // (charge recorded, refund didn't land — typically because
                // the ledger is locked from a corrupt blob, see #72/#119).
                // Distinct outcome so AppDelegate can post a stronger banner
                // ("обратитесь в поддержку") rather than the standard
                // "Откладывание не запланировано" message that implies money was returned.
                AppLogger.coordinator.fault(
                    """
                    snooze: schedule failed alarm=\(alarmID, privacy: .private) \
                    AND refund failed — wallet desync, manual reconciliation required
                    """
                )
                completion?(.scheduleFailedAndRefundFailed(error: error))
            }
        }
    }

    // MARK: - Pause / Resume (firing-time top-up, #141)
    //
    // The mid-firing top-up sheet needs to silence the alarm + freeze any
    // running escalation work while the user completes Apple Pay. The current
    // coordinator doesn't own a long-running timer (each `snooze` re-arms
    // `AlarmScheduler` then returns) so the pause/resume pair here is mostly
    // a delegation seam: it pauses the audio surface and logs the transition
    // so a future regression where pause/resume falls out of sync with the
    // audio session is diagnosable from Console alone. Owning the logic here
    // (rather than calling `AudioService` directly from the sheet VC) keeps
    // the pause contract atomic — when #138 lands the rewritten firing VC
    // and adds a real escalation timer, this is the single place that needs
    // to learn how to stop it.

    /// `true` while a top-up sheet is suppressing audio + escalation. Public
    /// read so tests can assert pause/resume parity without poking at private
    /// state.
    private(set) var isEscalationPaused: Bool = false

    /// Pauses any active escalation work + the alarm audio session.
    /// Called by `FiringTopUpBottomSheetViewController` on `viewWillAppear`
    /// so the alarm goes quiet while the user picks a preset. Idempotent —
    /// repeat calls are no-ops so the firing VC + the sheet can both arm the
    /// pause without coordinating.
    func pauseEscalation() {
        guard !isEscalationPaused else { return }
        isEscalationPaused = true
        AudioService.shared.pauseAlarmSound()
        AppLogger.coordinator.notice("escalation paused (top-up sheet open)")
    }

    /// Reverses `pauseEscalation()`. Called on sheet dismiss (cancel, success
    /// auto-dismiss, 60s timeout) so the alarm picks up where it left off.
    func resumeEscalation() {
        guard isEscalationPaused else { return }
        isEscalationPaused = false
        AudioService.shared.resumeAlarmSound()
        AppLogger.coordinator.notice("escalation resumed")
    }
}
