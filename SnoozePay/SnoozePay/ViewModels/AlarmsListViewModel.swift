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

    /// Toggle by stable UUID rather than row index. Cells should call this so the
    /// right alarm flips even after the list has been reordered or items deleted
    /// since the cell was configured. The historical `toggleAlarm(at:)` shim was
    /// removed in #79 — call sites must now resolve the UUID themselves so a
    /// stale row index can never flip the wrong alarm.
    func toggleAlarm(id: UUID, enabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else {
            // Stale cell closure or deleted alarm — the cell already flipped its visual
            // state in setEnabledAppearance. Force a re-bind so the list reverts to truth.
            assertionFailure("toggleAlarm: id \(id) not found (count=\(alarms.count))")
            AppLogger.ui.error("toggleAlarm called for missing id=\(id, privacy: .private)")
            onAlarmsUpdated?()
            return
        }

        // Pre-update the in-memory cache to the new enabled state so the
        // failure-rollback closure below can flip it back regardless of
        // whether the scheduler resolves synchronously (test mock) or
        // asynchronously (real `UNUserNotificationCenter`). If we waited to
        // mutate after `setEnabled` returns, a sync mock would fire its
        // closure first, set `.enabled = !enabled`, then the post-call
        // mutation would clobber the rollback (#129).
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

        let didUpdate = alarmRepository.setEnabled(enabled, id: id) { [weak self] result in
            // Scheduling outcome only fires on the successful-persist path.
            // On failure we roll BOTH the in-memory cache AND the on-disk
            // persisted state back to the previous `enabled` value — without
            // the disk-rollback the next cold-launch would re-read enabled=true
            // from UserDefaults while the notification still isn't registered,
            // re-introducing the very silent failure this fix addresses (#129).
            guard let self else { return }
            if case .failure(let error) = result {
                AppLogger.ui.notice(
                    "schedule failed during toggle id=\(id, privacy: .private); rolling back UI + disk"
                )
                if let idx = self.alarms.firstIndex(where: { $0.id == id }) {
                    self.alarms[idx].enabled = !enabled
                }
                // Persist the rollback. We pass `nil` completion so we don't
                // re-trigger this closure on the rollback's own scheduler call
                // (toggle-off does no schedule work; toggle-on rollback after
                // a failed enable becomes a disable — also no schedule work).
                _ = self.alarmRepository.setEnabled(!enabled, id: id, schedulingResult: nil)
                self.onLoadError?(error)
                self.onAlarmsUpdated?()
            }
        }
        guard didUpdate else {
            // Repository no longer has this alarm (deleted from another path)
            // or the store is locked due to a corrupt blob (issue #72).
            // The cell already optimistically flipped its switch in
            // setEnabledAppearance — resync from the source of truth and
            // re-bind so the UI rolls back (issue #35). If the store is
            // locked, surface the lock so the user knows toggles aren't
            // landing rather than blaming the toggle for "not working".
            AppLogger.ui.notice("setEnabled returned false; rolling back UI for id=\(id, privacy: .private)")
            // Use the checked variant on the rollback read so a decode failure
            // surfaces directly instead of returning [] and forcing the user
            // to infer corruption from the toggle silently snapping back
            // (issue #117). The persistBlocked branch below remains a separate
            // case because `setEnabled` can return false with a healthy store
            // (alarm deleted from another path, #35).
            do {
                alarms = try alarmRepository.fetchAllChecked()
            } catch let error as AlarmRepository.RepositoryError {
                alarms = []
                onLoadError?(error)
                onAlarmsUpdated?()
                return
            } catch {
                alarms = []
            }
            if alarmRepository.lastLoadFailed {
                onLoadError?(AlarmRepository.RepositoryError.persistBlocked)
            }
            onAlarmsUpdated?()
            return
        }
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
            AppLogger.ui.notice("deleteAlarm: id \(id, privacy: .private) not in current snapshot")
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

    // MARK: - Affordability hint

    /// Default penalty used when the user hasn't created any alarms yet
    /// (or every alarm has a non-positive penalty). Matches the
    /// `Alarm.init` default and the IAP "~N откладываний" copy in
    /// `TopUpViewController`. Kept as a constant so a single tweak
    /// covers both the empty-list hint and the topup subtitles.
    static let defaultPenaltyAmount: Double = 50

    /// Average penalty across all alarms, falling back to
    /// `defaultPenaltyAmount` when no alarms exist or every alarm has a
    /// non-positive penalty. Used by the alarms list balance card to
    /// render "Хватит на ~N откладываний". The mode (most-frequent
    /// penalty) is preferred over the arithmetic mean because the
    /// design hint reads more accurately when alarms are clustered
    /// around a single value (e.g. four alarms at 50 ₽ + one outlier
    /// at 200 ₽ should report "~50" not "~80").
    var averagePenalty: Double {
        let positives = alarms.map { $0.penaltyAmount }.filter { $0 > 0 }
        guard !positives.isEmpty else { return Self.defaultPenaltyAmount }
        // Mode — pick the penalty value that appears most often. Ties
        // resolve to the largest penalty (so the hint stays
        // conservative — it under-reports the snooze count rather than
        // promising more than the user can actually afford).
        var counts: [Double: Int] = [:]
        for value in positives {
            counts[value, default: 0] += 1
        }
        guard let mode = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }) else {
            return Self.defaultPenaltyAmount
        }
        return mode.key
    }

    /// Number of snoozes the user can currently afford given the
    /// current `balance` and `averagePenalty`. Floored — the list hint
    /// never advertises a fractional snooze. Returns 0 when the user is
    /// out of money so the warning banner can still fire.
    var affordableSnoozeCount: Int {
        let penalty = averagePenalty
        guard penalty > 0, balance > 0 else { return 0 }
        return Int(floor(balance / penalty))
    }

    /// Localised hint shown under the balance number on the alarms
    /// list: "Хватит на ~5 откладываний". Pluralisation follows
    /// Russian rules (1 / 2-4 / 5-20 buckets); the "~" prefix mirrors
    /// the topup-row copy.
    var affordabilityHint: String {
        let count = affordableSnoozeCount
        return "Хватит на ~\(count) \(Self.snoozeWord(for: count))"
    }

    /// `true` when the balance is at or below the low-balance
    /// threshold. The list shows a warning banner whenever this is
    /// true on view appear (see issue #142).
    var isLowBalance: Bool {
        balance <= Self.lowBalanceThreshold
    }

    /// Threshold for the low-balance warning banner. Matched against
    /// the raw `balance` (₽). 100 ₽ chosen because it's roughly 2
    /// snoozes at the default penalty — the warning gives the user
    /// runway to top up before the next charge fails.
    static let lowBalanceThreshold: Double = 100

    /// Russian pluralisation for "откладывание" — picks between
    /// `откладывание` (n=1, 21, 31…), `откладывания` (2-4, 22-24…) and
    /// `откладываний` (everything else, including 0 and 5-20). Local to
    /// this VM because the only consumer is the affordability hint;
    /// promote to a shared utility once a second screen needs it.
    private static func snoozeWord(for count: Int) -> String {
        let normalisedCount = abs(count)
        let mod10 = normalisedCount % 10
        let mod100 = normalisedCount % 100
        if mod10 == 1 && mod100 != 11 {
            return "откладывание"
        }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            return "откладывания"
        }
        return "откладываний"
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
}
