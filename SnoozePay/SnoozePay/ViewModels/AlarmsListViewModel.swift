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

    // MARK: - Observers

    /// Owned observer token. Removed in `deinit` to prevent the
    /// NotificationCenter from holding a stale reference after this VM dies
    /// (the ViewController owning it may outlive the VM in edge cases).
    private var balanceObserver: NSObjectProtocol?

    // MARK: - Init

    init(
        alarmRepository: AlarmRepository = AlarmRepository(),
        balanceService: BalanceService = .shared
    ) {
        self.alarmRepository = alarmRepository
        self.balanceService = balanceService

        balanceObserver = NotificationCenter.default.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let newBalance = note.userInfo?[BalanceService.balanceUserInfoKey] as? Double else { return }
            self.balance = newBalance
            self.onBalanceUpdated?(newBalance)
        }
    }

    deinit {
        if let token = balanceObserver {
            NotificationCenter.default.removeObserver(token)
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
        toggleAlarm(id: alarms[index].id, enabled: enabled)
    }

    /// Toggle by stable UUID rather than row index. Cells should call this so the
    /// right alarm flips even after the list has been reordered or items deleted
    /// since the cell was configured.
    func toggleAlarm(id: UUID, enabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else {
            // Stale cell closure or deleted alarm — the cell already flipped its visual
            // state in setEnabledAppearance. Force a re-bind so the list reverts to truth.
            assertionFailure("toggleAlarm: id \(id) not found (count=\(alarms.count))")
            print("[AlarmsListViewModel] toggleAlarm called for missing id=\(id)")
            onAlarmsUpdated?()
            return
        }

        let didUpdate = alarmRepository.setEnabled(enabled, id: id)
        guard didUpdate else {
            // Repository no longer has this alarm (deleted from another path).
            // The cell already optimistically flipped its switch in setEnabledAppearance —
            // resync from the source of truth and re-bind so the UI rolls back (issue #35).
            print("[AlarmsListViewModel] setEnabled returned false; rolling back UI for id=\(id)")
            alarms = alarmRepository.fetchAll()
            onAlarmsUpdated?()
            return
        }

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

    /// Cached formatter — avoids ~1ms per-call allocation that adds up in lists.
    /// Locale fixed to `en_US_POSIX` so the 24-hour format `HH:mm` is honoured
    /// regardless of the user's region (some locales otherwise render `7:00 AM`).
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func alarmTimeString(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        return Self.timeFormatter.string(from: alarms[index].time)
    }

    /// Detail line for alarm card: "Name - Days" (e.g. "Работа - Будни")
    func alarmDetail(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        let alarm = alarms[index]
        return "\(alarm.name) \u{2022} \(alarm.repeatDaysDescription)"
    }

    /// Penalty line for alarm card (e.g. "▲ ОТЛОЖИТЬ: 50 ₽")
    func alarmPenaltyString(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        return "▲ ОТЛОЖИТЬ: \(Int(alarms[index].penaltyAmount)) ₽"
    }

    func alarmSubtitle(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        let alarm = alarms[index]
        let days = alarm.repeatDaysDescription
        let penalty = "\(Int(alarm.penaltyAmount)) ₽"
        return "\(days) \u{00B7} \(penalty)"
    }
}
