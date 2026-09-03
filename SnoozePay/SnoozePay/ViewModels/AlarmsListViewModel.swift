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
    /// The user's configured "Цена откладывания по умолчанию". Backs the
    /// affordability hint when no enabled alarm has a price of its own (#546).
    private let alarmDefaults: AlarmDefaults
    /// Single source of truth for "is there any backend that can ring an
    /// alarm" (#428). Owned here rather than queried ad-hoc by the VC so the
    /// screen has exactly one place to read the state from. Internal (not
    /// private) so tests can assert which `NotificationCenter` it observes.
    let backendMonitor: AlarmBackendMonitor

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
    /// Fired on the main queue whenever the alarm-backend availability
    /// transitions (#428) — including the transition triggered by returning
    /// from iOS Settings, which is the whole point of the proactive guard.
    /// The VC re-renders the banner and re-evaluates the create/enable gate.
    var onBackendAvailabilityChanged: ((AlarmBackendAvailability) -> Void)?

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
                return Localized.text("alarms.error.rollback_persist_failed")
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
        notificationCenter: NotificationCenter = .default,
        alarmDefaults: AlarmDefaults = .shared,
        backendMonitor: AlarmBackendMonitor? = nil
    ) {
        self.alarmRepository = alarmRepository
        self.balanceService = balanceService
        self.transactionRepository = transactionRepository
        self.notificationCenter = notificationCenter
        self.alarmDefaults = alarmDefaults
        // Default the monitor onto the SAME center that was injected —
        // building it with a fresh `.default` would make every test that
        // carefully isolates `notificationCenter:` still observe process-global
        // activation, and a test-host activation would then drag
        // `AlarmScheduler.shared` / `UNUserNotificationCenter` into unit tests.
        self.backendMonitor = backendMonitor
            ?? AlarmBackendMonitor(notificationCenter: notificationCenter)

        // The monitor re-probes on every foreground activation on its own;
        // forwarding its transitions is all this VM has to do.
        self.backendMonitor.onChange = { [weak self] availability in
            self?.onBackendAvailabilityChanged?(availability)
        }

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
        // Surface a corrupt transaction ledger here too (#440). The weekly-delta
        // header reads the lossy `fetchAll`, which collapses a corrupt blob to
        // "no charges" and silently hides the row — so the main screen would give
        // no signal that financial history is unreadable (it would otherwise
        // surface only later on Statistics/Wallet, or when a snooze charge fails
        // at firing). Probe the checked variant and drive the same `onLoadError`
        // banner used for alarm/balance corruption.
        do {
            _ = try transactionRepository.fetchAllChecked()
        } catch let error as TransactionRepository.RepositoryError {
            onLoadError?(error)
        } catch {
            // Non-typed decode error — swallow to match the alarm-fetch fallback.
        }
        balance = balanceService.balance
        onAlarmsUpdated?()
        onBalanceUpdated?(balance)
        surfacePendingBalanceCorruption()
    }

    // MARK: - Alarm backend guard (#428)

    /// Current answer to "can a saved alarm actually ring". Read-only mirror of
    /// the monitor so no call site can drift into its own AlarmKit-or-
    /// notifications condition.
    var backendAvailability: AlarmBackendAvailability {
        backendMonitor.availability
    }

    /// Copy for the proactive banner, or `nil` when there's nothing to warn
    /// about. The VC mounts/dismounts the banner purely from this.
    var backendWarning: AlarmBackendWarning? {
        AlarmBackendWarning(availability: backendAvailability)
    }

    /// `false` only when we positively know NO backend can ring an alarm.
    /// An unresolved or indeterminate probe leaves the CTAs open — we never
    /// block the user on our own ignorance.
    var canCreateAlarms: Bool {
        backendWarning?.gatesAlarmCreation != true
    }

    /// Re-query authorization. Called on `viewWillAppear`; the monitor also
    /// re-queries itself on every app activation, so a permission flipped in
    /// iOS Settings lands without a cold launch.
    func refreshBackendAvailability() {
        backendMonitor.refresh()
    }

    /// Surface the OS permission dialog in place. Valid only while
    /// `backendWarning?.canRequestInApp == true` — afterwards the OS ignores
    /// the request and Settings is the only route, so callers must branch on
    /// the flag rather than calling this blindly.
    func requestAlarmPermissions() {
        guard backendWarning?.canRequestInApp == true else {
            AppLogger.ui.notice("requestAlarmPermissions ignored — OS grant already decided")
            return
        }
        backendMonitor.requestAuthorization()
    }

    /// Should tapping the "+" CTA be intercepted by the backend guard?
    var shouldInterceptCreate: Bool {
        !canCreateAlarms
    }

    /// Should flipping a row's switch be intercepted by the backend guard?
    /// Only switching ON is gated — turning an alarm OFF always works and must
    /// never raise the alert. Extracted from the VC so both halves of the
    /// condition are covered by tests rather than living in an untested
    /// double negative.
    func shouldInterceptToggle(isOn: Bool) -> Bool {
        isOn && !canCreateAlarms
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

        // Success path: the new enabled state is persisted (the `guard` above
        // passed). The cell repaints its own switch, but the sticky header's
        // affordability hint (`balanceHint`, derived from `currentSnoozePrice`)
        // shifts when an alarm with an outlier penalty is toggled — without a
        // refresh here the header pill keeps the stale "~N откладываний" number
        // until the next `viewWillAppear` (#429). `onBalanceUpdated` re-resolves
        // the header without a full table reload (the cell already updated). A
        // later async scheduling failure re-fires the header via the
        // rollback path's `onAlarmsUpdated`, re-syncing it to the reverted state.
        onBalanceUpdated?(balance)
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

    /// Price of one snooze as this screen quotes it — delegated to
    /// `SnoozeAffordability` so the wallet card answers with the exact same
    /// number (#546). Was `averagePenalty`, a "mode over ALL alarms" that
    /// degenerated into "the most expensive alarm" whenever every alarm had a
    /// different price, and that counted disabled alarms which can never
    /// charge anything.
    var currentSnoozePrice: Double {
        SnoozeAffordability.currentPrice(alarms: alarms, defaults: alarmDefaults)
    }

    /// Number of snoozes the user can currently afford given the
    /// current `balance` and `currentSnoozePrice`. Floored — the list hint
    /// never advertises a fractional snooze. Returns 0 when the user is
    /// out of money so the warning banner can still fire.
    var affordableSnoozeCount: Int {
        SnoozeAffordability.affordableCount(
            balance: balance,
            alarms: alarms,
            defaults: alarmDefaults
        )
    }

    /// Localised hint shown under the balance number on the alarms
    /// list: "Хватит на ~5 откладываний". Shared verbatim with the wallet
    /// balance card (#546).
    var affordabilityHint: String {
        SnoozeAffordability.hint(
            balance: balance,
            alarms: alarms,
            defaults: alarmDefaults
        )
    }

    // MARK: - Zero-balance state (#232)

    /// `true` when the user has literally no money. The header pill
    /// switches into its pain (zero) tone and the hint copy changes —
    /// distinct from `isLowBalance`, which only warns that the runway
    /// is short.
    var isZeroBalance: Bool {
        balance <= 0
    }

    /// Copy shown under the 0 ₽ figure. Deliberately "Откладывать не
    /// получится", NOT "будильники не зазвонят" — the alarm still fires
    /// at zero balance; the user just can't pay to snooze it (PM call,
    /// issue #232). Alarms stay visually active for the same reason.
    static var zeroBalanceHint: String { Localized.text("alarms.hint.zero_balance") }

    /// The single hint string the alarms-list header should render under
    /// the balance figure: zero-balance copy when the wallet is empty,
    /// otherwise the regular "Хватит на ~N откладываний" affordability
    /// line ("~0 откладываний" never ships — the zero branch wins first).
    var balanceHint: String {
        isZeroBalance ? Self.zeroBalanceHint : affordabilityHint
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
        // Exclude REFUNDED charges (a snooze that failed to schedule is auto-
        // refunded and per design "doesn't count") so the header doesn't
        // overstate the week's spend (#440). `realCharges` is computed over the
        // FULL ledger first — a charge refunded by a later top-up is still
        // excluded — then filtered to the rolling 7-day window.
        //
        // Checked read collapsed with `try?` (#271): this is a non-throwing
        // computed property, and a corrupt ledger must hide the row rather than
        // render a confident "0 ₽ за неделю". `loadData()` already raises the
        // banner that explains WHY the row is missing, so the collapse here is
        // deliberate and not a silent swallow.
        let ledger = (try? transactionRepository.fetchAllChecked()) ?? []
        let weekCharges = TransactionRepository.realCharges(from: ledger)
            .filter { $0.createdAt >= weekAgo }
        guard !weekCharges.isEmpty else { return nil }
        let totalCharged = weekCharges.reduce(0.0) { $0 + $1.amount }
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

    // MARK: - Helpers for cell display

    /// The list cells show the hour WITHOUT a leading zero ("7:30", "19:05")
    /// to match the prototype (artboard 06); the create/edit time picker keeps
    /// the padded form (`TimePickerCell`). See #343.
    ///
    /// The `en_US_POSIX` pin this used to carry forced 24 hours on everyone —
    /// which is right for a Russian region and wrong for an American one, and
    /// the width was never the part that needed pinning (#628).
    /// ``WallClockFormatter`` keeps the width and hands the cycle back to the
    /// locale, caching the formatter as this did.
    func alarmTimeString(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        return WallClockFormatter.string(from: alarms[index].time, style: .compact)
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
        return Localized.format(
            "alarms.penalty",
            MoneyFormatter.string(alarms[index].penaltyAmount)
        )
    }

    // MARK: - V2 cell helpers

    /// Caps-styled day label for the V2 card top row.
    /// Examples (weekly):
    ///  - `[0,1,2,3,4]`             → `БУДНИ · ПН–ПТ`
    ///  - `[5,6]`                   → `ВЫХОДНЫЕ`
    ///  - `[0,1,2,3,4,5,6]`         → `КАЖДЫЙ ДЕНЬ`
    ///  - `[]`                      → `ЕДИНОЖДЫ`
    ///  - `[1,3]`, with name "Спорт" → `СПОРТ · ВТ, ЧТ`
    ///  - `[0]`, name empty/default → `ПН`
    ///
    /// One-shot alarms (`repeatMode == .never`) with a non-empty day set are
    /// kept visually distinct from the weekly ones so the user can tell "rings
    /// once on the next Mon–Fri" apart from "rings every Mon–Fri" (#289):
    ///  - `.never`, `[0,1,2,3,4]`   → `ЕДИНОЖДЫ · ПН–ПТ`
    ///  - `.never`, `[1,3]`         → `ЕДИНОЖДЫ · ВТ, ЧТ`
    ///  - `.never`, `[]`            → `ЕДИНОЖДЫ`
    ///
    /// Combines the alarm's user-set `name` with the weekday set when the
    /// name is non-default — otherwise renders the weekday phrase alone. The
    /// alarm-list spec line "Спорт · Вт, Чт" lives here so the cell can stay
    /// a passive renderer.
    func alarmDaysCaps(at index: Int) -> String {
        guard index < alarms.count else { return "" }
        let alarm = alarms[index]
        let daysPhrase = Self.weekdayPhrase(
            for: alarm.repeatDays,
            repeatMode: alarm.repeatMode
        ).uppercased()
        let trimmed = alarm.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // The auto-assigned default name is suppressed here — it's the
        // boilerplate label every freshly-created alarm carries and would
        // crowd the caps line.
        //
        // This asks the MODEL whether the user ever typed a name (#623); it no
        // longer compares the persisted string against a literal. The old
        // comparison could only ever be right in one language: a name written
        // to disk in the locale the alarm was created in was matched against
        // the default spelled in the locale the reader happens to run, so the
        // first shipped translation turned "БУДНИ · ПН–ПТ" into
        // "ALARM · БУДНИ · ПН–ПТ". A whitespace-only name is still treated as
        // absent so the row never renders a dangling "·".
        let nameIsDefault = trimmed.isEmpty || alarm.nameIsDefault
        if nameIsDefault {
            return daysPhrase
        }
        return "\(trimmed.uppercased()) · \(daysPhrase)"
    }

    /// Weekday set rendered as a humanised Russian phrase. Mirrors
    /// `Alarm.repeatDaysDescription` shape but always returns a Russian
    /// label suitable for the caps line (no "Единожды" en dash collapsing
    /// the alarm into an unintelligible "·" pair when there's no name).
    ///
    /// `repeatMode` decides whether the weekly grouping aliases
    /// ("Будни · Пн–Пт", "Выходные", "Каждый день") apply: those imply a
    /// recurring alarm, so a one-shot (`.never`) alarm with days set instead
    /// renders "Единожды · <day list>" to stay distinguishable from the
    /// weekly variant (#289).
    static func weekdayPhrase(
        for days: [Int],
        repeatMode: AlarmRepeatMode = .weekly
    ) -> String {
        guard !days.isEmpty else { return Localized.text("alarms.days.once") }
        let names = WeekdayNames.short
        let sorted = days.sorted()
        let dayList = sorted.compactMap { index -> String? in
            guard index >= 0, index < names.count else { return nil }
            return names[index]
        }.joined(separator: ", ")
        if repeatMode == .never {
            return dayList.isEmpty
                ? Localized.text("alarms.days.once")
                : Localized.format("alarms.days.once_on", dayList)
        }
        if sorted == Array(0...6) { return Localized.text("alarms.days.every_day") }
        if sorted == [0, 1, 2, 3, 4] { return Localized.text("alarms.days.weekdays") }
        if sorted == [5, 6] { return Localized.text("alarms.days.weekend") }
        return dayList
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
    /// catalogue (a custom file, or a sound shipped after this build).
    ///
    /// Reads `SoundCatalogue.nameKey(for:)` (#599) instead of the ten private
    /// literals this method used to carry. Those literals were a verbatim copy
    /// of the picker's names, and #598 had already moved the picker's half into
    /// `Localizable.xcstrings` and exposed the key spelling as a seam precisely
    /// so this side could collapse onto it rather than mint a second set of
    /// keys for the same ten words. `SoundCatalogueCopyTests`
    /// `.testAlarmsListStillRendersTheSameWordsAsTheCatalogue` was written
    /// against the duplication and now pins the collapse as changing no copy.
    ///
    /// `optionalText` rather than `text`, which is what `SoundCatalogue.entries`
    /// uses: `text` echoes the key on a miss, and the documented behaviour of
    /// *this* call site is to fall back to the raw id. A cell reading
    /// «common.sound.name.foo» would be a regression against a pill that reads
    /// «foo», so the miss is resolved here and not by the shared reader.
    func alarmSoundName(at index: Int) -> String? {
        guard index < alarms.count else { return nil }
        let soundID = alarms[index].soundID
        return Localized.optionalText(SoundCatalogue.nameKey(for: soundID)) ?? soundID
    }
}
