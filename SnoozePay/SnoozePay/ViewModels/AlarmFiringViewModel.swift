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
    /// Read-only view of the transaction ledger. Post-factum money figures
    /// («сегодня списано N ₽», the history ticker) are derived from THIS, not
    /// from `snoozeCount` — see `billedSnoozes` (#400).
    private let ledger: AlarmFiringLedgerReading
    private var snoozeSessions: AlarmSnoozeSessionStore?
    private(set) var snoozeReference: AlarmSnoozeReference?
    private(set) var isProgressionAvailable = true

    /// Called before mounting through the existing screen factory/read-back path.
    func bindSnoozeSession(_ reference: AlarmSnoozeReference, store: AlarmSnoozeSessionStore) {
        snoozeSessions = store
        snoozeReference = reference
        do {
            guard case .token(let token) = reference else { throw AlarmSnoozeContextError.unavailable }
            let snapshot = try store.resolve(token, alarmID: alarm.id)
            snoozeCount = snapshot.count
            confirmedSnoozeFireDate = snapshot.fireDate
            isProgressionAvailable = true
        } catch {
            isProgressionAvailable = false
            confirmedSnoozeFireDate = nil
            snoozeAnchor = nil
            AppLogger.emit(.ui, .error, "Snooze session unavailable — refusing paid continuation")
        }
    }

    // MARK: - State

    let alarm: Alarm
    /// Snooze ATTEMPTS in this wake — every «Поспать ещё» whose charge landed,
    /// including one whose trigger the scheduler later rejected (the penalty is
    /// refunded but the attempt still happened). Drives everything FORWARD-
    /// looking: the next price, the ladder, the escalation gradient. It is
    /// deliberately NOT the source for what was actually billed — that is
    /// `billedSnoozes`, read from the ledger (#400).
    private(set) var snoozeCount: Int

    /// Confirmed snooze's tap moment, captured ONCE in `snooze()` and published
    /// only after scheduling succeeds. The visual countdown anchors to this
    /// FIXED instant (`snoozeAnchor + snoozeMinutes`) so the live countdown
    /// ticks down against a moving `now` and actually reaches `0` (issue #396).
    /// It must equal what the scheduler arms — `AlarmScheduler.scheduledFireDate`
    /// = tap moment + snoozeMinutes — so the in-app countdown and the real
    /// re-ring agree even when the user snoozes minutes after the alarm fired.
    /// `nil` before confirmation, after failure, and after Stop.
    private(set) var snoozeAnchor: Date?
    private var confirmedSnoozeFireDate: Date?

    /// Prevent another debit while the current scheduling result is unresolved.
    private(set) var isSnoozeScheduling = false
    private var hasBeenDismissed = false

    /// Moment this firing session was mounted. Anchors the ledger window the
    /// billed-charge summary looks back over (`wakeWindow`), so charges from
    /// yesterday's wake of the SAME alarm can never leak into today's total.
    /// Not the start of the ring on screen once the user has snoozed: that is
    /// `lastRingStartedAt`.
    let firingStartedAt: Date

    /// When the ring on screen started: the re-ring the last snooze armed
    /// (`nextRingDate()`), or `firingStartedAt` before any snooze.
    /// `AlarmFiringPresenter` tells the current ring from an older one by it;
    /// by `firingStartedAt`, a snooze past its window read as stale (#855).
    var lastRingStartedAt: Date { nextRingDate() ?? firingStartedAt }

    // MARK: - Callbacks

    var onStateChanged: (() -> Void)?

    // MARK: - Init

    init(
        alarm: Alarm,
        snoozeCount: Int = 0,
        snoozeAnchor: Date? = nil,
        balanceService: AlarmFiringBalancing = BalanceService.shared,
        alarmRepository: AlarmRepository = .shared,
        scheduler: AlarmScheduler = .shared,
        wakeStore: WakeEventStore = .shared,
        ledger: AlarmFiringLedgerReading = TransactionRepository.shared,
        firingStartedAt: Date = Date(),
        snoozeSessions: AlarmSnoozeSessionStore? = nil
    ) {
        self.alarm = alarm
        self.snoozeCount = snoozeCount
        self.snoozeAnchor = snoozeAnchor
        self.balanceService = balanceService
        self.alarmRepository = alarmRepository
        self.scheduler = scheduler
        self.wakeStore = wakeStore
        self.ledger = ledger
        self.firingStartedAt = firingStartedAt
        self.snoozeSessions = snoozeSessions
    }

    // MARK: - Computed properties for UI

    var currentPenalty: Double {
        isProgressionAvailable ? alarm.penalty(forSnoozeCount: snoozeCount + 1) : .nan
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

    // MARK: - Billed history from the ledger (#400)

    /// How far back of the ledger belongs to the CURRENT wake. A snooze chain
    /// can only stretch a few hours (`snoozeMinutes` × attempts), so 12 h is
    /// generous — and, being well under 24 h, it also guarantees that a charge
    /// from yesterday's firing of the same alarm falls outside the window.
    /// A fixed offset rather than "start of calendar day" so a 23:50 alarm
    /// snoozed past midnight still reports its pre-midnight charges.
    static let wakeWindow: TimeInterval = 12 * 60 * 60

    /// Existing ledger-health bound for each charge and this wake's aggregate.
    /// Currency projection must not hide implausible rows in another currency.
    static let maxPlausibleCharge: Double = 1e9

    /// What the ledger says the user was ACTUALLY billed for this wake.
    ///
    /// Deriving the on-screen money from `snoozeCount` × the doubling rule was
    /// the bug in #400: a snooze whose trigger the scheduler rejected is
    /// charged, then **refunded**, yet still bumps `snoozeCount` — so the
    /// summary claimed money the user got back. The ledger is the only place
    /// that knows which charges survived.
    enum BilledSnoozes: Equatable {
        /// Ledger read cleanly — every non-reversed penalty of this wake,
        /// oldest first.
        case known([Double])
        /// The ledger could not be read (decode failure), carried rows this
        /// build can't classify, or held a non-finite/negative amount. Any
        /// total computed from it would be a guess, so callers MUST NOT render
        /// a rouble figure — they hide the number or say so plainly.
        case unavailable
    }

    /// Read on demand (no caching) so a refund landing asynchronously, a
    /// top-up, or a charge from another surface is reflected the next time the
    /// firing screen refreshes. Reads are serialised inside the repository, and
    /// `updateUI()` is event-driven (state change / balance notification), not
    /// per clock tick, so this is not on a hot path.
    var billedSnoozes: BilledSnoozes {
        guard let charges = loadBilledChargeRows() else { return .unavailable }
        return .known(charges.map(\.amount))
    }

    /// Legacy unscoped amounts actually billed this wake, oldest first. The
    /// currency-labelled ticker uses `pastPenalties(in:)` instead. Empty
    /// before the first billed snooze — and also when the ledger is
    /// unreadable, which hides the ticker rather than inventing amounts.
    var pastPenalties: [Double] {
        guard case .known(let amounts) = billedSnoozes else { return [] }
        return amounts
    }

    /// Financial ticker projection. Refund pairing and ledger health checks
    /// still see the complete history before selecting the displayed currency.
    func pastPenalties(in currency: Currency) -> [Double] {
        loadBilledChargeRows()?.filter { $0.currency == currency }.map(\.amount) ?? []
    }

    struct MorningBilling {
        let billedCount: Int
        let walletTotal: Double
    }

    /// Count every surviving charge, but quote money only in the wallet currency.
    /// Both projections share one checked read, so a refund cannot split them.
    func morningBilling(in currency: Currency) -> MorningBilling? {
        guard let charges = loadBilledChargeRows() else { return nil }
        return MorningBilling(
            billedCount: charges.count,
            walletTotal: charges.filter { $0.currency == currency }.reduce(0) { $0 + $1.amount }
        )
    }

    /// Legacy unscoped total across this wake's surviving charges.
    /// Currency-labelled summaries use `morningBilling(in:)` instead.
    /// Nil preserves unreadable history rather than fabricating a zero (#400).
    var chargedThisMorning: Double? {
        guard case .known(let amounts) = billedSnoozes else { return nil }
        return amounts.reduce(0, +)
    }

    /// Snoozes the user was actually BILLED for this wake — `snoozeCount`
    /// minus any attempt whose penalty was refunded. `nil` when the ledger is
    /// unreadable, same contract as `chargedThisMorning`.
    ///
    /// Currency-labelled count/sum pairs use `morningBilling(in:)`; legacy
    /// unscoped pairs use one `billedSnoozes` snapshot. Separate convenience
    /// reads can disagree if an asynchronous refund lands between them.
    var billedSnoozeCount: Int? {
        guard case .known(let amounts) = billedSnoozes else { return nil }
        return amounts.count
    }

    /// Pulls this wake's surviving charges out of the ledger.
    ///
    /// Every failure mode returns `nil` instead of an empty/partial
    /// total: this number is money the user is told they lost, so "we couldn't
    /// read it" must never render as "0 ₽" (the `try? … ?? []` trap, #210).
    private func loadBilledChargeRows() -> [Transaction]? {
        let all: [Transaction]
        do {
            all = try ledger.fetchAllChecked()
        } catch {
            let desc = String(describing: error)
            AppLogger.ui.error(
                "firing summary: ledger unreadable (\(desc, privacy: .public)) — charged total suppressed"
            )
            return nil
        }
        // A row whose `type` token this build can't classify is skipped by
        // every aggregate, including `realCharges` — so the total would be
        // silently short. Treat it as unreadable too (#358 surfaced the flag
        // for exactly this).
        guard !ledger.lastLoadHadUnrecognizedTypes else {
            AppLogger.ui.error(
                "firing summary: ledger holds unrecognised transaction types — charged total suppressed"
            )
            return nil
        }

        let windowStart = firingStartedAt.addingTimeInterval(-Self.wakeWindow)
        let alarmKey = alarm.id.uuidString
        // `realCharges` must see the WHOLE ledger — a refund row lives outside
        // any window/alarm filter, and dropping it first would resurrect the
        // charge it reverses.
        let charges = TransactionRepository.realCharges(from: all)
            .filter { $0.alarmID == alarmKey && $0.createdAt >= windowStart }
            .sorted { $0.createdAt < $1.createdAt }
        let amounts = charges.map(\.amount)
        // Legacy rows predate the finite/positive guard in `chargeWithReceipt`
        // (#441); invalid or implausible amounts make the summary untrustworthy
        // even when they belong to another currency.
        guard amounts.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= Self.maxPlausibleCharge }) else {
            AppLogger.ui.error(
                "firing summary: ledger holds an implausible charge amount — charged total suppressed"
            )
            return nil
        }
        // Retain the same global aggregate bound before projecting currency.
        let total = amounts.reduce(0, +)
        guard total.isFinite, total <= Self.maxPlausibleCharge else {
            AppLogger.ui.error(
                "firing summary: charges sum beyond the plausible range — charged total suppressed"
            )
            return nil
        }
        return charges
    }

    var canSnooze: Bool {
        isProgressionAvailable && balanceService.canAfford(currentPenalty)
    }

    var snoozeButtonTitle: String {
        guard isProgressionAvailable else { return Localized.text("firing.progression.unavailable") }
        if canSnooze {
            return Localized.format(
                "firing.snooze.button.affordable",
                alarm.snoozeMinutes,
                MoneyFormatter.string(currentPenalty)
            )
        } else {
            return Localized.text("firing.snooze.button.no_balance")
        }
    }

    var balance: Double { balanceService.balance }
    var walletCurrency: Currency { balanceService.walletCurrency }
    func acceptsPurchase(in currency: Currency) -> Bool { balanceService.acceptsPurchase(in: currency) }

    var alarmName: String { alarm.name }

    /// Whether AlarmKit currently owns the alarm sound. Every production snooze
    /// must await `.scheduled` before dismissing, even if authorization changes.
    var usesAlarmKit: Bool { scheduler.usesAlarmKit }

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
        let amount: Double
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
        let amounts = (1...4).map { alarm.penalty(forSnoozeCount: $0) }
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

    /// Fixed wall-clock target of a confirmed snooze. Tracked production schedules use
    /// the actual date returned by AlarmKit, including backend latency or flooring.
    /// An explicit `anchor`, or an untracked legacy snooze, uses the stored tap moment
    /// plus `snoozeMinutes` through `AlarmScheduler.scheduledFireDate` (#396).
    /// The target stays constant while `now` advances, so the countdown reaches zero.
    /// Returns `nil` before confirmation and after finish.
    func nextRingDate(anchor: Date? = nil) -> Date? {
        if anchor == nil, let confirmedSnoozeFireDate { return confirmedSnoozeFireDate }
        guard let tap = anchor ?? snoozeAnchor else { return nil }
        return AlarmScheduler.scheduledFireDate(now: tap, snoozeMinutes: alarm.snoozeMinutes)
    }

    /// Wall-clock label of the next ring — «отложено до 07:05» / status-bar
    /// time. Padded hour, in whatever cycle the reader's locale uses (#628);
    /// it was a hardcoded `HH:mm` until that issue.
    /// Empty before the first snooze (no anchor → no target).
    func nextRingTimeText(anchor: Date? = nil) -> String {
        guard let target = nextRingDate(anchor: anchor) else { return "" }
        return AlarmFiringTimeFormatter.string(from: target)
    }

    /// Hero name + next-ring suffix shown in the snoozed state, e.g.
    /// "Будни · отложено до 07:05". Degrades to "отложено до …" when the alarm
    /// has no name, so the row never renders a dangling "·".
    func snoozedHeroTitle(anchor: Date? = nil) -> String {
        let time = nextRingTimeText(anchor: anchor)
        let name = alarm.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = Localized.format("firing.snoozed.suffix", time)
        return name.isEmpty ? suffix : "\(name) · \(suffix)"
    }

    /// Remaining seconds until the next ring (never negative), measured from the
    /// FIXED snooze target (`snoozeAnchor + snoozeMinutes`) to the MOVING `now`.
    /// Because the target is fixed while `now` advances, the value decrements
    /// every tick and reaches `0` at the re-ring — which is when the firing
    /// screen restores the active state. `0` when there is no anchor yet (no
    /// snooze taken) so the snoozed chrome never installs prematurely.
    func secondsUntilNextRing(from now: Date, anchor: Date? = nil) -> Int {
        guard let target = nextRingDate(anchor: anchor) else { return 0 }
        return max(0, Int(target.timeIntervalSince(now).rounded()))
    }

    /// `mm:ss` countdown label clamped at `00:00`. Static so the formatting is
    /// testable from a raw second count without a clock.
    static func countdownText(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// "Будни · 07:00" hero title above the big clock — alarm name plus its
    /// scheduled time (V3 themed firing, handoff only — the canon has none),
    /// `docs/design/v2-handoff/components/SPThemedFiring.jsx:152` contains "Будни · 07:00".
    /// A blank / whitespace-only name degrades to just the time so the row
    /// never renders a dangling "·" separator.
    var heroTitle: String {
        let time = AlarmFiringTimeFormatter.string(from: alarm)
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
        guard !hasBeenDismissed, !isSnoozeScheduling, canSnooze else { return false }
        isSnoozeScheduling = true

        // Capture the penalty for this snooze BEFORE bumping the count so the
        // refund (if the schedule fails) returns the exact amount charged.
        let penalty = currentPenalty
        let token: AlarmSnoozeToken?
        do {
            if snoozeSessions != nil {
                guard let current = try alarmRepository.fetchChecked(id: alarm.id), current.enabled else {
                    throw AlarmSnoozeContextError.finished
                }
            }
            let sessionID: UUID?
            if case .token(let bound)? = snoozeReference { sessionID = bound.sessionID } else { sessionID = nil }
            token = try snoozeSessions?.reserve(alarmID: alarm.id, sessionID: sessionID, expectedCount: snoozeCount)
            if let token { snoozeReference = .token(token) }
        } catch {
            isProgressionAvailable = false
            isSnoozeScheduling = false
            onStateChanged?()
            return false
        }
        // `chargeWithReceipt` surfaces the persisted charge transaction so a
        // later refund can link back to it via `refundsTransactionID` (issue
        // #366). Without that link the foreground refund offsets the balance
        // but the original charge still inflates snooze stats / streak, the
        // exact bug #133 fixed for the notification-action path only.
        guard let chargeTransaction = balanceService.chargeWithReceipt(
            amount: penalty,
            alarmID: alarm.id
        ) else {
            if let token {
                do { try snoozeSessions?.rejectCharge(token, alarmID: alarm.id) } catch {
                    isProgressionAvailable = false
                    onStateChanged?()
                }
            }
            isSnoozeScheduling = false
            return false
        }

        snoozeCount += 1
        // Keep the tap instant, but publish a next-ring promise only once the
        // scheduler confirms it. A rejected attempt leaves no countdown target.
        let anchor = Date()
        snoozeAnchor = nil
        confirmedSnoozeFireDate = nil
        onStateChanged?()
        let finish: (Result<Void, AlarmScheduler.SchedulingError>) -> Void = { [self] result in
            // Retain this operation until its refund/outcome resolves, even if the VC disappears.
            isSnoozeScheduling = false
            if case .success = result {
                if hasBeenDismissed || !isProgressionAvailable {
                    // Stop may have cancelled before the async backend created
                    // this trigger. Cancel again so a late success cannot re-arm.
                    if token == nil { scheduler.cancel(alarm.id) }
                } else {
                    snoozeAnchor = anchor
                }
            }
            handleScheduleResult(
                result,
                penalty: penalty,
                chargeTransactionID: chargeTransaction.id
            ) { outcome in
                self.onStateChanged?()
                scheduleCompletion?(outcome)
            }
        }
        guard let token, let snoozeSessions else {
            scheduler.scheduleSnooze(for: alarm, snoozeCount: snoozeCount, completion: finish)
            return true
        }
        do {
            try snoozeSessions.recordCharge(token, alarmID: alarm.id)
        } catch {
            isProgressionAvailable = false
            finish(.failure(.system(message: error.localizedDescription)))
            return true
        }
        scheduler.scheduleTrackedSnooze(for: alarm, token: token) { [self] result in
            let mapped = result.mapError { error in
                (error as? AlarmScheduler.SchedulingError) ?? .system(message: error.localizedDescription)
            }
            do {
                if case .failure(let error) = result,
                   case .unconfirmedRegistration? = error as? AlarmSnoozeContextError { throw error }
                let receipt: AlarmSnoozeReceipt?
                switch result {
                case .success(let registered): receipt = registered
                case .failure: receipt = nil
                }
                try snoozeSessions.complete(token, alarmID: alarm.id, receipt: receipt)
                confirmedSnoozeFireDate = receipt?.fireDate
                finish(mapped.map { _ in () })
            } catch {
                isProgressionAvailable = false
                snoozeSessions.operationEnded(token)
                scheduler.cleanUpTrackedSnooze(alarm.id)
                if hasBeenDismissed {
                    finish(mapped.map { _ in () })
                } else {
                    finish(.failure(.system(message: error.localizedDescription)))
                }
            }
        }
        return true
    }

    /// Resolves the async scheduler result, refunding the penalty on failure so
    /// the foreground snooze path matches `AlarmFiringCoordinator
    /// .handleScheduleResult` (issue #197). Extracted for a dedicated log seam.
    private func handleScheduleResult(
        _ result: Result<Void, AlarmScheduler.SchedulingError>,
        penalty: Double,
        chargeTransactionID: UUID,
        completion: ((SnoozeScheduleOutcome) -> Void)?
    ) {
        switch result {
        case .success:
            completion?(.scheduled)
        case .failure(let error):
            // `snoozeCount` is deliberately NOT rolled back here (#400). It
            // counts ATTEMPTS and drives forward-looking state — the next
            // price, the ladder rung, the escalation gradient — so decrementing
            // it would hand out a cheaper next snooze every time the scheduler
            // hiccups, and would race a second tap that already read the old
            // value. The user is made whole by the refund, and the post-factum
            // money display no longer reads `snoozeCount` at all: it comes from
            // the ledger via `billedSnoozes`, which drops this reversed charge.
            //
            // Refund via `refund` (an offsetting ledger entry) rather than
            // mutating storage directly, so transaction history shows both the
            // charge and the refund and stats stay auditable. Link the refund
            // to the original charge so `realCharges(from:)` excludes the
            // reversed snooze from stats / streak (issue #366 / #133). Must not
            // go through `topUp` — that books the reversal as paid IAP revenue
            // (issue #358).
            let refunded = balanceService.refund(
                amount: penalty,
                refundsTransactionID: chargeTransactionID
            )
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
        hasBeenDismissed = true
        do { try snoozeSessions?.finish(alarmID: alarm.id) } catch {
            let detail = String(describing: error)
            AppLogger.emit(.ui, .error, "Snooze finish persistence failed: \(detail)")
        }
        snoozeAnchor = nil
        confirmedSnoozeFireDate = nil
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
/// protocol lets tests inject a stub that can fail `refund` independently of
/// `charge` — the only way to exercise the `scheduleFailedAndRefundFailed`
/// branch, since `BalanceService` / `TransactionRepository` are `final` and a
/// locked ledger fails `charge` too (issue #197).
protocol AlarmFiringBalancing: AnyObject {
    var balance: Double { get }
    var walletCurrency: Currency { get }
    func acceptsPurchase(in currency: Currency) -> Bool
    func canAfford(_ amount: Double) -> Bool
    /// Charges the penalty and returns the persisted charge `Transaction` (or
    /// `nil` on insufficient funds / locked ledger). The returned `id` lets the
    /// foreground snooze path link an offsetting refund back to this charge via
    /// `refund(amount:refundsTransactionID:)` so a reversed snooze is excluded
    /// from stats — closing the gap #133 left on the foreground path (#366).
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction?
    /// Reverses a penalty as a `.refund` ledger row — deliberately NOT `topUp`,
    /// which is reserved for paid IAP credit and drives revenue accounting
    /// (issue #358). `refundsTransactionID` links the reversal to the charge it
    /// offsets so the charge is excluded from snooze stats (issue #133). Both
    /// the foreground snooze path and the notification-action path supply it
    /// (#366).
    @discardableResult func refund(amount: Double, refundsTransactionID: UUID?) -> Bool
}

extension BalanceService: AlarmFiringBalancing {}

// MARK: - Ledger seam (#400)

/// The read-only slice of `TransactionRepository` the firing VM needs to report
/// what was ACTUALLY billed this wake.
///
/// Only the *checked* read is exposed: the lossy `fetchAll()` turns a corrupt
/// ledger into "no charges", which on this screen means telling the user their
/// money is intact when we have no idea (#210). `lastLoadHadUnrecognizedTypes`
/// rides along because an unclassifiable row is skipped by every aggregate and
/// would silently understate the total (#358).
protocol AlarmFiringLedgerReading: AnyObject {
    func fetchAllChecked() throws -> [Transaction]
    var lastLoadHadUnrecognizedTypes: Bool { get }
}

extension TransactionRepository: AlarmFiringLedgerReading {}
