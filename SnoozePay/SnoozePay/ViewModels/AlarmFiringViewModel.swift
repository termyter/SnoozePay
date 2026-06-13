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

    /// Amount charged by the MOST RECENT snooze — the rung the user just paid
    /// for. `snooze()` bumps `snoozeCount` before this reads, so it equals
    /// `penalty(forSnoozeCount: snoozeCount)`. Drives the fly-up «−N ₽» in the
    /// snoozed state. `0` before the first snooze.
    var lastChargeAmount: Double {
        snoozeCount > 0 ? alarm.penalty(forSnoozeCount: snoozeCount) : 0
    }

    // MARK: - Snoozed state (#226)

    /// Per-step state of the 4-rung charge ladder rendered in the snoozed
    /// firing chrome (`SPFiringThemeSnoozed.jsx`). `done` rungs are already
    /// paid, `current` is the rung the user will pay on the NEXT snooze (it
    /// matches the snooze CTA's next-step price and the «N-й поспать ещё» pill,
    /// where N = snoozeCount + 1), `future` rungs are still ahead. Pure value
    /// type so the ladder layout is unit-testable without a view hierarchy.
    enum LadderStepState: Equatable {
        case done
        case current
        case future
    }

    /// One rung of the charge ladder: its amount (₽) plus its state.
    struct LadderStep: Equatable {
        let amount: Int
        let state: LadderStepState
    }

    /// The 4-rung progressive charge ladder for the snoozed state. Amounts are
    /// the doubling schedule `base, ×2, ×4, ×8` (the same ceiling
    /// `penalty(forSnoozeCount:)` walks). State keys off `snoozeCount`: rungs
    /// strictly before it are `done` (already paid), the rung AT `snoozeCount`
    /// is `current` — the NEXT charge (after paying rung `i` the user has
    /// snoozed `i+1` times, so `snoozeCount` indexes the next unpaid rung, which
    /// is why it lines up with the CTA's next-step price) — and the rest are
    /// `future`. `snoozeCount` past the last rung clamps `current` to rung 4 so
    /// the ladder never blanks out at the ceiling. Returns `[]` when the alarm
    /// isn't progressive (the snoozed state hides the ladder entirely).
    var ladderSteps: [LadderStep] {
        guard isProgressiveActive else { return [] }
        let base = alarm.penaltyAmount
        let amounts = (0..<4).map { Int((base * pow(2.0, Double($0))).rounded()) }
        let currentIdx = min(snoozeCount, amounts.count - 1)
        return amounts.enumerated().map { idx, amount in
            let state: LadderStepState
            if idx < currentIdx {
                state = .done
            } else if idx == currentIdx {
                state = .current
            } else {
                state = .future
            }
            return LadderStep(amount: amount, state: state)
        }
    }

    /// Wall-clock `Date` of the next ring after the current snooze — the
    /// alarm's time-of-day shifted forward `snoozeMinutes × snoozeCount`
    /// minutes, anchored to `reference`'s calendar day. Pure (takes `now` +
    /// `calendar`) so the countdown maths is testable without the system clock.
    func nextRingDate(after reference: Date, calendar: Calendar = .current) -> Date {
        let timeParts = calendar.dateComponents([.hour, .minute], from: alarm.time)
        let base = calendar.date(
            bySettingHour: timeParts.hour ?? 0,
            minute: timeParts.minute ?? 0,
            second: 0,
            of: reference
        ) ?? reference
        return base.addingTimeInterval(TimeInterval(alarm.snoozeMinutes * snoozeCount * 60))
    }

    /// `HH:mm` label of the next ring — "отложено до 07:05" / status-bar time.
    func nextRingTimeText(after reference: Date, calendar: Calendar = .current) -> String {
        AlarmFiringTimeFormatter.string(from: nextRingDate(after: reference, calendar: calendar))
    }

    /// Hero name + next-ring suffix shown in the snoozed state, e.g.
    /// "Будни · отложено до 07:05". Degrades to "отложено до …" when the alarm
    /// has no name, so the row never renders a dangling "·".
    func snoozedHeroTitle(after reference: Date, calendar: Calendar = .current) -> String {
        let time = nextRingTimeText(after: reference, calendar: calendar)
        let name = alarm.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = "отложено до \(time)"
        return name.isEmpty ? suffix : "\(name) · \(suffix)"
    }

    /// Remaining seconds until the next ring (never negative). Used by the live
    /// countdown; at `0` the firing screen restores the active state.
    func secondsUntilNextRing(from reference: Date, calendar: Calendar = .current) -> Int {
        let target = nextRingDate(after: reference, calendar: calendar)
        return max(0, Int(target.timeIntervalSince(reference).rounded()))
    }

    /// `mm:ss` countdown label clamped at `00:00`. Static so the formatting is
    /// testable from a raw second count without a clock.
    static func countdownText(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// "Будни · 07:00" hero title above the big clock — alarm name plus its
    /// scheduled time (V3 themed firing, `SPThemedFiring.jsx` line 152).
    /// A blank / whitespace-only name degrades to just the time so the row
    /// never renders a dangling "·" separator.
    var heroTitle: String {
        let time = AlarmFiringTimeFormatter.string(from: alarm.time)
        let name = alarm.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? time : "\(name) · \(time)"
    }

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
    /// Non-repeating alarms — no selected days, or one-shot `repeatMode ==
    /// .never` (#229) — are disabled after dismissal. Disabling a one-shot
    /// alarm also drops its remaining per-day triggers via the
    /// `scheduler.cancel` call above, so "ring once and switch off" holds
    /// even when several weekdays were selected.
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

        if alarm.repeatDays.isEmpty || alarm.repeatMode == .never {
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
