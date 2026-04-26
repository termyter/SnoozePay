import Foundation
import os

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
    /// Fired when a repository read or write fails. The VC presents an
    /// alert so the user understands the empty list isn't them losing
    /// their alarms (issue #72). Carries a `LocalizedError` whose
    /// `errorDescription` is already user-facing Russian copy.
    var onLoadError: ((LocalizedError) -> Void)?

    // MARK: - Observers

    /// Owned observer token. Removed in `deinit` to prevent the
    /// NotificationCenter from holding a stale reference after this VM dies
    /// (the ViewController owning it may outlive the VM in edge cases).
    private var balanceObserver: NSObjectProtocol?

    // MARK: - Init

    init(
        alarmRepository: AlarmRepository = .shared,
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
        // Use the checked variant so a corrupt UserDefaults blob shows the
        // user a banner instead of a deceptive empty list — otherwise they
        // assume their alarms were wiped, recreate them, and the next
        // persist clobbers the recoverable JSON for good (issue #72).
        do {
            alarms = try alarmRepository.fetchAllChecked()
        } catch let error as AlarmRepository.RepositoryError {
            alarms = []
            onLoadError?(error)
        } catch {
            alarms = []
        }
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
            AppLogger.alarms.warning("toggleAlarm called for missing id=\(id, privacy: .private)")
            onAlarmsUpdated?()
            return
        }

        let didUpdate = alarmRepository.setEnabled(enabled, id: id)
        guard didUpdate else {
            // Repository no longer has this alarm (deleted from another path)
            // or the store is locked due to a corrupt blob (issue #72).
            // The cell already optimistically flipped its switch in
            // setEnabledAppearance — resync from the source of truth and
            // re-bind so the UI rolls back (issue #35). If the store is
            // locked, surface the lock so the user knows toggles aren't
            // landing rather than blaming the toggle for "not working".
            AppLogger.alarms.warning("setEnabled returned false; rolling back UI for id=\(id, privacy: .private)")
            alarms = alarmRepository.fetchAll()
            if alarmRepository.lastLoadFailed {
                onLoadError?(AlarmRepository.RepositoryError.persistBlocked)
            }
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
        deleteAlarm(id: alarms[index].id)
    }

    /// Identity-based delete — preferred over index-based when triggered by
    /// async UI events (swipe handlers) where the visible index may have
    /// drifted from the data-source row by the time the action fires.
    @discardableResult
    func deleteAlarm(id: UUID) -> Bool {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else {
            AppLogger.alarms.warning("deleteAlarm: id \(id, privacy: .private) not in current snapshot")
            return false
        }
        let didDelete = alarmRepository.delete(id: id)
        guard didDelete else {
            // Persist was blocked (corrupt store) or encode failed — keep
            // the in-memory snapshot intact and surface the failure so the
            // user doesn't think the swipe-to-delete worked (issue #72).
            onLoadError?(AlarmRepository.RepositoryError.persistBlocked)
            return false
        }
        alarms.remove(at: index)
        return true
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
