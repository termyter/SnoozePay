import Foundation
import os

/// ViewModel for the alarm firing screen.
/// Manages penalty calculation and balance deduction logic.
final class AlarmFiringViewModel {

    // MARK: - Outcome

    /// Result of the in-app (firing VC) snooze, reported asynchronously once
    /// the scheduler confirms whether the next trigger registered. Mirrors
    /// `AlarmFiringCoordinator.SnoozeOutcome`'s failure semantics so the
    /// foreground path and the notification-action path surface the same UX
    /// (issue #197 — the foreground call site had no refund-on-failure).
    enum SnoozeScheduleOutcome: Equatable {
        /// Charge succeeded and the next snooze trigger registered.
        case scheduled
        /// Charge succeeded but the scheduler rejected the trigger. The penalty
        /// has been **refunded** before this is reported — the user is not
        /// billed for a snooze that won't re-fire. Surface a banner so they set
        /// a backup alarm.
        case scheduleFailed(AlarmScheduler.SchedulingError)
        /// Charge succeeded, schedule failed, AND the offsetting refund also
        /// failed (locked ledger from a corrupt blob). Wallet is degraded —
        /// money taken, no re-fire, refund didn't land. Surface a stronger
        /// "contact support" banner.
        case scheduleFailedAndRefundFailed(AlarmScheduler.SchedulingError)
    }

    // MARK: - Dependencies

    private let balanceService: AlarmFiringBalancing
    private let alarmRepository: AlarmRepository
    private let scheduler: AlarmScheduler
    private let wakeStore: WakeEventStore

    // MARK: - State

    let alarm: Alarm
    private(set) var snoozeCount: Int

    // MARK: - Callbacks

    var onStateChanged: (() -> Void)?

    // MARK: - Init

    init(
        alarm: Alarm,
        snoozeCount: Int = 0,
        balanceService: AlarmFiringBalancing = BalanceService.shared,
        alarmRepository: AlarmRepository = .shared,
        scheduler: AlarmScheduler = .shared,
        wakeStore: WakeEventStore = .shared
    ) {
        self.alarm = alarm
        self.snoozeCount = snoozeCount
        self.balanceService = balanceService
        self.alarmRepository = alarmRepository
        self.scheduler = scheduler
        self.wakeStore = wakeStore
    }

    // MARK: - Computed properties for UI

    var currentPenalty: Double {
        alarm.penalty(forSnoozeCount: snoozeCount + 1)
    }

    // MARK: - Progressive escalation (#139)

    /// `true` when the firing screen should render the progressive escalation
    /// chrome: the warn → pain gradient cross-fade on the snooze CTA, the
    /// "Прогрессив · N-е откладывание" indicator pill, and the history ticker.
    /// Mirrors the underlying alarm setting so default alarms keep the plain
    /// warn-tone Dawn treatment from #138.
    var isProgressiveActive: Bool { alarm.progressiveScale }

    /// Cross-fade weight between the warn and pain gradient stops. `0.0` on
    /// the very first snooze (snoozeCount == 0), reaching `1.0` once the
    /// user has hit the 6th snooze of the morning. Linear ramp because the
    /// PM brief reads as "gradually redden" — easing curves muddied which
    /// snooze count produced which colour during prototyping.
    var progressiveIntensity: Double {
        guard isProgressiveActive else { return 0 }
        return max(0.0, min(1.0, Double(snoozeCount) / 5.0))
    }

    /// Past penalty amounts charged today, in chronological order, derived
    /// from the same doubling rule as `currentPenalty`. Used by the firing
    /// screen's history ticker to render "сегодня: −50 → −100 → ..." without
    /// hitting the balance ledger (the in-VC string is purely informational).
    /// Returns `[]` until the user has snoozed at least once.
    var pastPenalties: [Double] {
        guard snoozeCount > 0 else { return [] }
        return (1...snoozeCount).map { alarm.penalty(forSnoozeCount: $0) }
    }

    var canSnooze: Bool {
        balanceService.canAfford(currentPenalty)
    }

    var snoozeButtonTitle: String {
        if canSnooze {
            return "+\(alarm.snoozeMinutes) минут · −\(MoneyFormatter.string(currentPenalty))"
        } else {
            return "Баланс пуст"
        }
    }

    var balance: Double { balanceService.balance }

    var alarmName: String { alarm.name }

    // MARK: - Actions

    /// Deduct penalty and reschedule snooze.
    /// Returns true if charge + snoozeCount bump succeeded. The optional
    /// `scheduleCompletion` is invoked AFTER the underlying scheduler reports
    /// the result of registering the snooze trigger with iOS — if it fires
    /// `.failure(SchedulingError)` the user has already been charged but the
    /// alarm will NOT actually re-fire. The VC must surface the error so the
    /// user knows to set a backup alarm (or contact support for refund).
    /// Without consuming this completion the original silent-failure-class
    /// from #118 reappears in the snooze flow (silent-failure-hunter #127).
    ///
    /// On scheduler failure the penalty is **refunded** before the outcome is
    /// reported (issue #197) — mirroring `AlarmFiringCoordinator`'s
    /// notification-action path so the user is never billed for a snooze that
    /// won't re-fire. `scheduleCompletion` therefore reports a richer
    /// `SnoozeScheduleOutcome` (not the raw scheduler `Result`) so the VC can
    /// distinguish a clean refund from a degraded "refund also failed" wallet.
    @discardableResult
    func snooze(
        scheduleCompletion: ((SnoozeScheduleOutcome) -> Void)? = nil
    ) -> Bool {
        guard canSnooze else { return false }

        // Capture the penalty for this snooze BEFORE bumping the count so the
        // refund (if the schedule fails) returns the exact amount charged.
        let penalty = currentPenalty
        let charged = balanceService.charge(amount: penalty, alarmID: alarm.id)
        guard charged else { return false }

        snoozeCount += 1
        scheduler.scheduleSnooze(for: alarm, snoozeCount: snoozeCount) { [weak self] result in
            self?.handleScheduleResult(result, penalty: penalty, completion: scheduleCompletion)
        }
        onStateChanged?()
        return true
    }

    /// Resolves the async scheduler result, refunding the penalty on failure so
    /// the foreground snooze path matches `AlarmFiringCoordinator
    /// .handleScheduleResult` (issue #197). Extracted for a dedicated log seam.
    private func handleScheduleResult(
        _ result: Result<Void, AlarmScheduler.SchedulingError>,
        penalty: Double,
        completion: ((SnoozeScheduleOutcome) -> Void)?
    ) {
        switch result {
        case .success:
            completion?(.scheduled)
        case .failure(let error):
            // Refund via `topUp` (an offsetting ledger entry) rather than
            // mutating storage directly, so transaction history shows both the
            // charge and the refund and stats stay auditable.
            let refunded = balanceService.topUp(amount: penalty)
            let desc = error.errorDescription ?? error.localizedDescription
            if refunded {
                AppLogger.ui.error(
                    """
                    foreground snooze: schedule failed alarm=\(self.alarm.id, privacy: .private) \
                    refunded=\(penalty, privacy: .public) reason=\(desc, privacy: .public)
                    """
                )
                completion?(.scheduleFailed(error))
            } else {
                // Refund itself failed — wallet desync (charge recorded, refund
                // didn't land — locked ledger from a corrupt blob, #72/#119).
                AppLogger.ui.fault(
                    """
                    foreground snooze: schedule failed alarm=\(self.alarm.id, privacy: .private) \
                    AND refund failed — wallet desync, manual reconciliation required
                    """
                )
                completion?(.scheduleFailedAndRefundFailed(error))
            }
        }
    }

    /// Dismiss the alarm without charge.
    /// Non-repeating alarms are disabled after dismissal.
    ///
    /// `setEnabled` returns `false` when the alarm is no longer in the repository
    /// (e.g. user deleted it from another screen while the firing UI was up).
    /// In that case the desired end-state ("disabled") is already true, so we
    /// only surface a diagnostic — no UI rollback or user-facing error needed
    /// (issue #54 mirrors the silent-failure fix from #35 for the list path).
    func dismiss() {
        // The user got up — feed the behavioural statistics heatmap (#235).
        // Recorded per calendar day; the snooze count for the day comes from
        // the charge ledger, so "встал сразу" = wake event + zero charges.
        wakeStore.recordWake()
        scheduler.cancel(alarm.id)

        if alarm.repeatDays.isEmpty {
            let didUpdate = alarmRepository.setEnabled(false, id: alarm.id)
            if !didUpdate {
                AppLogger.ui.notice("dismiss: alarm \(self.alarm.id, privacy: .private) already removed from repository")
            }
        }
    }
}

// MARK: - Billing seam

/// The slice of `BalanceService` the firing VM depends on. Declaring it as a
/// protocol lets tests inject a stub that can fail `topUp` independently of
/// `charge` — the only way to exercise the `scheduleFailedAndRefundFailed`
/// branch, since `BalanceService` / `TransactionRepository` are `final` and a
/// locked ledger fails `charge` too (issue #197).
protocol AlarmFiringBalancing: AnyObject {
    var balance: Double { get }
    func canAfford(_ amount: Double) -> Bool
    @discardableResult func charge(amount: Double, alarmID: UUID?) -> Bool
    @discardableResult func topUp(amount: Double) -> Bool
}

extension BalanceService: AlarmFiringBalancing {}
