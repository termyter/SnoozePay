import Foundation

/// ViewModel for the alarms list screen.
/// Manages the alarm collection, balance display, and toggle state.
final class AlarmsListViewModel {

    // MARK: - Dependencies

    private let alarmRepository: AlarmRepository
    private let balanceService: BalanceService

    // MARK: - State

    private(set) var alarms: [Alarm] = []
    private(set) var balance: Double = 0

    // MARK: - Callbacks (ViewController binds these)

    var onAlarmsUpdated: (() -> Void)?
    var onBalanceUpdated: ((Double) -> Void)?

    // MARK: - Init

    init(
        alarmRepository: AlarmRepository = AlarmRepository(),
        balanceService: BalanceService = .shared
    ) {
        self.alarmRepository = alarmRepository
        self.balanceService = balanceService

        balanceService.onBalanceChanged = { [weak self] newBalance in
            self?.balance = newBalance
            self?.onBalanceUpdated?(newBalance)
        }
    }

    // MARK: - Load

    func loadData() {
        alarms = alarmRepository.fetchAll()
        balance = balanceService.balance
        onAlarmsUpdated?()
        onBalanceUpdated?(balance)
    }

    // MARK: - Toggle

    func toggleAlarm(at index: Int, enabled: Bool) {
        guard index < alarms.count else { return }
        alarmRepository.setEnabled(enabled, id: alarms[index].id)
        alarms[index] = Alarm(
            id: alarms[index].id,
            time: alarms[index].time,
            repeatDays: alarms[index].repeatDays,
            name: alarms[index].name,
            soundID: alarms[index].soundID,
            vibrationEnabled: alarms[index].vibrationEnabled,
            snoozeMinutes: alarms[index].snoozeMinutes,
            penaltyAmount: alarms[index].penaltyAmount,
            progressiveScale: alarms[index].progressiveScale,
            enabled: enabled
        )
    }

    // MARK: - Delete

    func deleteAlarm(at index: Int) {
        guard index < alarms.count else { return }
        alarmRepository.delete(id: alarms[index].id)
        alarms.remove(at: index)
    }

    // MARK: - Formatted balance

    var formattedBalance: String {
        "\(Int(balance)) ₽"
    }

    // MARK: - Helpers for cell display

    func alarmTimeString(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: alarms[index].time)
    }

    func alarmSubtitle(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        let alarm = alarms[index]
        let days = alarm.repeatDaysDescription
        let penalty = "\(Int(alarm.penaltyAmount)) ₽"
        return "\(days) · \(penalty)"
    }
}
