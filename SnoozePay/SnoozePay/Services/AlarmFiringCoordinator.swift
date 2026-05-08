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

        // `chargeWithReceipt` returns the persisted Transaction so a later
        // refund can link back to it (issue #133) — without that link stats
        // can't tell a refunded charge apart from a real snooze.
        guard let chargeTransaction = balanceService.chargeWithReceipt(
            amount: penalty,
            alarmID: payload.alarmID
        ) else {
            let alarmID = payload.alarmID
            AppLogger.coordinator.notice(
                "snooze: insufficient funds alarm=\(alarmID, privacy: .private) penalty=\(penalty, privacy: .public)"
            )
            completion?(.insufficientFunds)
            return
        }

        scheduler.scheduleSnooze(for: alarm, snoozeCount: newCount) { [weak self] result in
            self?.handleScheduleResult(
                result,
                alarmID: payload.alarmID,
                newCount: newCount,
                penalty: penalty,
                chargeTransactionID: chargeTransaction.id,
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
        chargeTransactionID: UUID,
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
            // Link the refund to the original charge ID so stats consumers
            // can pair the two rows (issue #133); without the link a refund
            // still inflates snoozeCount/totalSpent and resets streak.
            let refunded = balanceService.topUp(
                amount: penalty,
                refundsTransactionID: chargeTransactionID
            )
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
                // ("обратитесь в поддержку") rather than the standard "снуз
                // не запланирован" message that implies money was returned.
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
}
