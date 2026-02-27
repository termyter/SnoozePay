import Foundation

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
        alarmRepository: AlarmRepository = AlarmRepository(),
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
    /// Returns true if snooze was successful.
    @discardableResult
    func snooze() -> Bool {
        guard canSnooze else { return false }

        let charged = balanceService.charge(amount: currentPenalty, alarmID: alarm.id)
        guard charged else { return false }

        snoozeCount += 1
        scheduler.scheduleSnooze(for: alarm, snoozeCount: snoozeCount)
        onStateChanged?()
        return true
    }

    /// Dismiss the alarm without charge.
    func dismiss() {
        scheduler.cancel(alarm.id)
    }
}
