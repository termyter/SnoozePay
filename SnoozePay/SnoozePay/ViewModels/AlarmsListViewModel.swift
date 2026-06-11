import Foundation
import os

/// ViewModel for the alarms list screen.
/// Manages the alarm collection, balance display, and toggle state.
final class AlarmsListViewModel {

    // MARK: - Dependencies

    private let alarmRepository: AlarmRepository
    private let balanceService: BalanceService
    private let transactionRepository: TransactionRepository
    private let notificationCenter: NotificationCenter

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
    /// Fired (once per corruption episode) when the stored balance is
    /// corrupt — negative / NaN / infinite `user_balance` (#119). Carries the
    /// raw offending value. The VC presents an alert offering to wipe the
    /// corrupt value via `acknowledgeBalanceCorruption()`. Covers BOTH the
    /// live notification AND corruption latched at cold start before this VM
    /// existed — `loadData()` pulls the latched state from the service, since
    /// `NotificationCenter` does not retro-deliver to late subscribers (#206).
    var onBalanceCorrupted: ((Double) -> Void)?

    // MARK: - Errors

    /// Surfaced via `onLoadError` when the disk rollback after a failed
    /// schedule also fails (#205). In-memory and persisted `enabled` state
    /// have diverged at that point — only a relaunch (which re-reads disk)
    /// reconciles them, so the copy tells the user to re-check the list.
    enum ToggleError: LocalizedError {
        case rollbackPersistFailed

        var errorDescription: String? {
            switch self {
            case .rollbackPersistFailed:
                return "Не удалось включить будильник и откатить изменение — "
                    + "данные могут быть в рассинхроне. Перезапустите приложение "
                    + "и проверьте список будильников."
            }
        }
    }

    // MARK: - Observers

    /// Owned observer token. Removed in `deinit` to prevent the
    /// NotificationCenter from holding a stale reference after this VM dies
    /// (the ViewController owning it may outlive the VM in edge cases).
    private var balanceObserver: NSObjectProtocol?

    /// Observer token for `balanceCorruptedNotification` — covers corruption
    /// that latches while this VM is alive. Cold-start corruption (latched in
    /// `BalanceService.init` before any observer exists) is instead pulled in
    /// `loadData()` via `surfacePendingBalanceCorruption()` (#206).
    private var corruptionObserver: NSObjectProtocol?

    /// Dedupe latch so the corruption alert fires once per episode even
    /// though `loadData()` runs on every `viewWillAppear` (and the live
    /// notification + the pulled state could otherwise double-fire). Reset
    /// in `acknowledgeBalanceCorruption()` so a future re-corruption is
    /// surfaced again.
    private var hasSurfacedBalanceCorruption = false

    // MARK: - Init

    init(
        alarmRepository: AlarmRepository = .shared,
        balanceService: BalanceService = .shared,
        transactionRepository: TransactionRepository = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.alarmRepository = alarmRepository
        self.balanceService = balanceService
        self.transactionRepository = transactionRepository
        self.notificationCenter = notificationCenter

        balanceObserver = notificationCenter.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let newBalance = note.userInfo?[BalanceService.balanceUserInfoKey] as? Double else { return }
            self.balance = newBalance
            self.onBalanceUpdated?(newBalance)
        }

        corruptionObserver = notificationCenter.addObserver(
            forName: BalanceService.balanceCorruptedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[BalanceService.balanceCorruptedRawValueKey] as? Double else { return }
            self.surfaceBalanceCorruption(rawValue: raw)
        }
    }

    deinit {
        if let token = balanceObserver {
            notificationCenter.removeObserver(token)
        }
        if let token = corruptionObserver {
            notificationCenter.removeObserver(token)
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
        surfacePendingBalanceCorruption()
    }

    // MARK: - Balance corruption (#119 / #206)

    /// Pulls corruption state latched BEFORE this VM registered its observer
    /// (cold start: AppDelegate materializes `BalanceService.shared`, whose
    /// init-time probe posts `balanceCorruptedNotification` with no listener
    /// attached — the event is dropped, see #206). Called from `loadData()`,
    /// which the VC invokes after binding callbacks, so the alert is
    /// guaranteed a live `onBalanceCorrupted` handler.
    private func surfacePendingBalanceCorruption() {
        guard balanceService.balanceCorrupted else { return }
        surfaceBalanceCorruption(rawValue: balanceService.corruptedRawValue ?? balance)
    }

    private func surfaceBalanceCorruption(rawValue: Double) {
        guard !hasSurfacedBalanceCorruption else { return }
        hasSurfacedBalanceCorruption = true
        onBalanceCorrupted?(rawValue)
    }

    /// Wipes the corrupt `user_balance` (resets to 0) after the user
    /// confirmed in the alert. `BalanceService` broadcasts
    /// `balanceChangedNotification` on success, which refreshes this VM's
    /// `balance` via the regular observer. The dedupe latch is reset so a
    /// future corruption episode surfaces a fresh alert.
    func acknowledgeBalanceCorruption() {
        balanceService.acknowledgeCorruption()
        hasSurfacedBalanceCorruption = false
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
        //
        // Use `with(enabled:)` rather than rebuilding `Alarm` field-by-field —
        // the manual rebuild silently dropped any field it didn't list (it
        // reset `volume`/`volumeFadeIn`/`theme` from #150/#151 to their
        // defaults) and would do the same for every future field (#205).
        // `with` copies every other field through unchanged (#207).
        alarms[index] = alarms[index].with(enabled: enabled)

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
                    self.alarms[idx] = self.alarms[idx].with(enabled: !enabled)
                }
                // Persist the rollback. We pass `nil` completion so we don't
                // re-trigger this closure on the rollback's own scheduler call
                // (toggle-off does no schedule work; toggle-on rollback after
                // a failed enable becomes a disable — also no schedule work).
                let rollbackPersisted = self.alarmRepository.setEnabled(
                    !enabled, id: id, schedulingResult: nil
                )
                if rollbackPersisted {
                    self.onLoadError?(error)
                } else {
                    // The disk rollback itself failed (store locked mid-flight
                    // or alarm deleted concurrently): in-memory now says
                    // `!enabled` while UserDefaults still says `enabled`. On
                    // the next cold launch the app re-reads enabled=true with
                    // no notification registered — the silent regression #129
                    // was designed to close. Surface a stronger banner than
                    // the scheduling error alone and log at fault level so
                    // the drift is visible in sysdiagnose (#205).
                    AppLogger.repository.fault(
                        """
                        toggle rollback persist failed id=\(id, privacy: .private); \
                        in-memory and disk enabled state diverged
                        """
                    )
                    self.onLoadError?(ToggleError.rollbackPersistFailed)
                }
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
        MoneyFormatter.string(balance)
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

    /// Weekly net delta surfaced in the sticky header beneath the balance
    /// (#175). Charge transactions are penalty deductions stored as
    /// positive `Double`s with `type == .charge`, so the user-facing net
    /// change versus a week ago is `-sum(charges)`. Returns `nil` when
    /// there are no charges in the last 7 days so the header hides the
    /// row entirely (matches `components.css` L163-165 — `.is-up` /
    /// `.is-down` are opt-in via `setBalance`).
    var weeklyDelta: Decimal? {
        // Anchor against `now - 7 days` rather than the start of an ISO
        // week — the user reads "за неделю" as a rolling 7-day window,
        // and an ISO-week boundary would make Monday morning's header
        // briefly show "0 ₽" until the first charge of the new week.
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else {
            return nil
        }
        let charges = transactionRepository.fetchCharges(since: weekAgo)
        guard !charges.isEmpty else { return nil }
        let totalCharged = charges.reduce(0.0) { $0 + $1.amount }
        guard totalCharged > 0 else { return nil }
        return -Decimal(totalCharged)
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

    /// Penalty line for alarm card (e.g. "▲ ПОСПАТЬ ЕЩЁ: −50 ₽")
    func alarmPenaltyString(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        return "▲ ПОСПАТЬ ЕЩЁ: −\(MoneyFormatter.string(alarms[index].penaltyAmount))"
    }

    // MARK: - V2 cell helpers

    /// Caps-styled day label for the V2 card top row.
    /// Examples:
    ///  - `[0,1,2,3,4]`             → `БУДНИ · ПН–ПТ`
    ///  - `[5,6]`                   → `ВЫХОДНЫЕ`
    ///  - `[0,1,2,3,4,5,6]`         → `КАЖДЫЙ ДЕНЬ`
    ///  - `[]`                      → `ЕДИНОЖДЫ`
    ///  - `[1,3]`, with name "Спорт" → `СПОРТ · ВТ, ЧТ`
    ///  - `[0]`, name empty/default → `ПН`
    ///
    /// Combines the alarm's user-set `name` with the weekday set when the
    /// name is non-default — otherwise renders the weekday phrase alone. The
    /// alarm-list spec line "Спорт · Вт, Чт" lives here so the cell can stay
    /// a passive renderer.
    func alarmDaysCaps(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        let alarm = alarms[index]
        let daysPhrase = Self.weekdayPhrase(for: alarm.repeatDays).uppercased()
        let trimmed = alarm.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Default name "Будильник" is suppressed in the caps row — it's the
        // boilerplate label every freshly-created alarm carries and would
        // crowd the caps line.
        let nameIsDefault = trimmed.isEmpty || trimmed.lowercased() == "будильник"
        if nameIsDefault {
            return daysPhrase
        }
        return "\(trimmed.uppercased()) · \(daysPhrase)"
    }

    /// Weekday set rendered as a humanised Russian phrase. Mirrors
    /// `Alarm.repeatDaysDescription` shape but always returns a Russian
    /// label suitable for the caps line (no "Единожды" en dash collapsing
    /// the alarm into an unintelligible "·" pair when there's no name).
    private static func weekdayPhrase(for days: [Int]) -> String {
        guard !days.isEmpty else { return "Единожды" }
        let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        let sorted = days.sorted()
        if sorted == Array(0...6) { return "Каждый день" }
        if sorted == [0, 1, 2, 3, 4] { return "Будни · Пн–Пт" }
        if sorted == [5, 6] { return "Выходные" }
        return sorted.compactMap { index -> String? in
            guard index >= 0, index < names.count else { return nil }
            return names[index]
        }.joined(separator: ", ")
    }

    /// Price pill text — bare "50 ₽" formatted via `Decimal.formattedRubles`
    /// so digit grouping matches the balance display.
    func alarmPriceText(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        return Decimal(alarms[index].penaltyAmount).formattedRubles()
    }

    /// Progressive-pain multiplier label. Returns `"×2"` when the alarm has
    /// the progressive scale toggle on, else `nil` so the cell hides the
    /// pill. The exact factor is informational — the firing screen
    /// computes the actual penalty per snooze count.
    func alarmMultiplierText(at index: Int) -> String? {
        guard index < alarms.count else { return nil }
        return alarms[index].progressiveScale ? "×2" : nil
    }

    /// Human-readable name of the alarm's picked sound (e.g. "Рассвет",
    /// "Радар"). Falls back to the raw `soundID` when the id isn't in the
    /// known catalogue (custom file or new sound not yet added to the
    /// lookup table).
    func alarmSoundName(at index: Int) -> String? {
        guard index < alarms.count else { return nil }
        let soundID = alarms[index].soundID
        return Self.soundDisplayNames[soundID] ?? soundID
    }

    /// Sound-id → Russian display-name lookup. Mirrors the
    /// `CreateAlarmViewModel.availableSounds` list so cells render the same
    /// label the user picked in the editor without coupling the alarms-list
    /// VM to the editor VM.
    private static let soundDisplayNames: [String: String] = [
        "dawn": "Рассвет",
        "radar": "Радар",
        "drops": "Капли",
        "piano": "Пиано",
        "guitar": "Гитара",
        "bell": "Колокольчик",
        "waves": "Волны",
        "birds": "Птицы",
        "classic": "Классика",
        "jazz": "Джаз"
    ]
}
