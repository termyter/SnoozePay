import Foundation
import os

/// ViewModel for the alarm firing screen.
/// Manages penalty calculation and balance deduction logic.
final class AlarmFiringViewModel {

    // MARK: - Dependencies

    private let balanceService: BalanceService
    private let alarmRepository: AlarmRepository
    private let scheduler: AlarmScheduler

    // MARK: - State

    let alarm: Alarm
    private(set) var snoozeCount: Int

    // MARK: - Callbacks

    var onStateChanged: (() -> Void)?

    // MARK: - Init

    init(
        alarm: Alarm,
        snoozeCount: Int = 0,
        balanceService: BalanceService = .shared,
        alarmRepository: AlarmRepository = .shared,
        scheduler: AlarmScheduler = .shared
    ) {
        self.alarm = alarm
        self.snoozeCount = snoozeCount
        self.balanceService = balanceService
        self.alarmRepository = alarmRepository
        self.scheduler = scheduler
    }

    // MARK: - Computed properties for UI

    var currentPenalty: Double {
        alarm.penalty(forSnoozeCount: snoozeCount + 1)
    }

    // MARK: - Progressive escalation (#139)

    /// `true` when the firing screen should render the progressive escalation
    /// chrome: the warn → pain gradient cross-fade on the snooze CTA, the
    /// "Прогрессив · N-й снуз" indicator pill, and the history ticker.
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
            return "Отложить · \(Int(currentPenalty)) ₽"
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
    @discardableResult
    func snooze(
        scheduleCompletion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)? = nil
    ) -> Bool {
        guard canSnooze else { return false }

        let charged = balanceService.charge(amount: currentPenalty, alarmID: alarm.id)
        guard charged else { return false }

        snoozeCount += 1
        scheduler.scheduleSnooze(
            for: alarm,
            snoozeCount: snoozeCount,
            completion: scheduleCompletion
        )
        onStateChanged?()
        return true
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
        scheduler.cancel(alarm.id)

        if alarm.repeatDays.isEmpty {
            let didUpdate = alarmRepository.setEnabled(false, id: alarm.id)
            if !didUpdate {
                AppLogger.ui.notice("dismiss: alarm \(self.alarm.id, privacy: .private) already removed from repository")
            }
        }
    }
}
