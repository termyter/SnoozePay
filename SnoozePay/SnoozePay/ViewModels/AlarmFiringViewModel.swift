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

    // MARK: - State

    let alarm: Alarm
    /// Snooze ATTEMPTS in this wake — every «Поспать ещё» whose charge landed,
    /// including one whose trigger the scheduler later rejected (the penalty is
    /// refunded but the attempt still happened). Drives everything FORWARD-
    /// looking: the next price, the ladder, the escalation gradient. It is
    /// deliberately NOT the source for what was actually billed — that is
    /// `billedSnoozes`, read from the ledger (#400).
    private(set) var snoozeCount: Int

    /// Wall-clock moment the user last tapped «Поспать ещё», captured ONCE per
    /// snooze in `snooze()`. The snoozed countdown anchors its target to this
    /// FIXED instant (`snoozeAnchor + snoozeMinutes`) so the live countdown
    /// ticks down against a moving `now` and actually reaches `0` (issue #396).
    /// It must equal what the scheduler arms — `AlarmScheduler.scheduledFireDate`
    /// = tap moment + snoozeMinutes — so the in-app countdown and the real
    /// re-ring agree even when the user snoozes minutes after the alarm fired.
    /// `nil` before the first snooze (the active firing UI shows no countdown).
    private(set) var snoozeAnchor: Date?

    /// Moment this firing session was mounted. Anchors the ledger window the
    /// billed-charge summary looks back over (`wakeWindow`), so charges from
    /// yesterday's wake of the SAME alarm can never leak into today's total.
    private let firingStartedAt: Date

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
        firingStartedAt: Date = Date()
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

    // MARK: - Billed history from the ledger (#400)

    /// How far back of the ledger belongs to the CURRENT wake. A snooze chain
    /// can only stretch a few hours (`snoozeMinutes` × attempts), so 12 h is
    /// generous — and, being well under 24 h, it also guarantees that a charge
    /// from yesterday's firing of the same alarm falls outside the window.
    /// A fixed offset rather than "start of calendar day" so a 23:50 alarm
    /// snoozed past midnight still reports its pre-midnight charges.
    static let wakeWindow: TimeInterval = 12 * 60 * 60

    /// Largest per-charge amount the summary will believe (1 млрд ₽). Rows this
    /// big can only come from ledger damage or a pre-#441 write, and they are
    /// not merely wrong: the display path narrows the total to `Int`, and
    /// `Int(1e300.rounded())` **traps** (SIGTRAP) rather than saturating. The
    /// bound keeps that conversion — and the running sum — inside `Int`'s range
    /// for any plausible row count.
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
    var billedSnoozes: BilledSnoozes { loadBilledSnoozes() }

    /// Penalty amounts actually billed this wake, oldest first. Feeds the
    /// firing screen's history ticker ("сегодня: −50 → −100 → ..."). Empty
    /// before the first billed snooze — and also when the ledger is
    /// unreadable, which hides the ticker rather than inventing amounts.
    var pastPenalties: [Double] {
        guard case .known(let amounts) = billedSnoozes else { return [] }
        return amounts
    }

    /// Total roubles the user is actually out of pocket this wake. Drives the
    /// WokeMorning «recovered» subtitle "Сегодня списано N ₽" (#228); `0` when
    /// the user got up on the first ring. **`nil` when the ledger is
    /// unreadable** — the caller must then show the no-figure variant instead
    /// of a fabricated sum (#400).
    var chargedThisMorning: Double? {
        guard case .known(let amounts) = billedSnoozes else { return nil }
        return amounts.reduce(0, +)
    }

    /// Snoozes the user was actually BILLED for this wake — `snoozeCount`
    /// minus any attempt whose penalty was refunded. `nil` when the ledger is
    /// unreadable, same contract as `chargedThisMorning`.
    ///
    /// A caller that renders BOTH the count and the sum must take a single
    /// `billedSnoozes` snapshot instead of reading these two convenience
    /// accessors: each one re-reads the ledger, and an async refund landing
    /// between the two reads would put a count and a total from different
    /// snapshots on the same screen.
    var billedSnoozeCount: Int? {
        guard case .known(let amounts) = billedSnoozes else { return nil }
        return amounts.count
    }

    /// Pulls this wake's surviving charges out of the ledger.
    ///
    /// Every failure mode returns `.unavailable` instead of an empty/partial
    /// total: this number is money the user is told they lost, so "we couldn't
    /// read it" must never render as "0 ₽" (the `try? … ?? []` trap, #210).
    private func loadBilledSnoozes() -> BilledSnoozes {
        let all: [Transaction]
        do {
            all = try ledger.fetchAllChecked()
        } catch {
            let desc = String(describing: error)
            AppLogger.ui.error(
                "firing summary: ledger unreadable (\(desc, privacy: .public)) — charged total suppressed"
            )
            return .unavailable
        }
        // A row whose `type` token this build can't classify is skipped by
        // every aggregate, including `realCharges` — so the total would be
        // silently short. Treat it as unreadable too (#358 surfaced the flag
        // for exactly this).
        guard !ledger.lastLoadHadUnrecognizedTypes else {
            AppLogger.ui.error(
                "firing summary: ledger holds unrecognised transaction types — charged total suppressed"
            )
            return .unavailable
        }

        let windowStart = firingStartedAt.addingTimeInterval(-Self.wakeWindow)
        let alarmKey = alarm.id.uuidString
        // `realCharges` must see the WHOLE ledger — a refund row lives outside
        // any window/alarm filter, and dropping it first would resurrect the
        // charge it reverses.
        let amounts = TransactionRepository.realCharges(from: all)
            .filter { $0.alarmID == alarmKey && $0.createdAt >= windowStart }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.amount)
        // Legacy rows predate the finite/positive guard in `chargeWithReceipt`
        // (#441); one NaN would render the summary as "списано nan ₽", and an
        // absurd magnitude would TRAP on the `Int` narrowing the summary does.
        guard amounts.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= Self.maxPlausibleCharge }) else {
            AppLogger.ui.error(
                "firing summary: ledger holds an implausible charge amount — charged total suppressed"
            )
            return .unavailable
        }
        // Belt for the same trap on the aggregate: a ledger stuffed with
        // in-range rows could still sum past what the display can narrow.
        let total = amounts.reduce(0, +)
        guard total.isFinite, total <= Self.maxPlausibleCharge else {
            AppLogger.ui.error(
                "firing summary: charges sum beyond the plausible range — charged total suppressed"
            )
            return .unavailable
        }
        return .known(amounts)
    }

    var canSnooze: Bool {
        balanceService.canAfford(currentPenalty)
    }

    var snoozeButtonTitle: String {
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

    var alarmName: String { alarm.name }

    /// `true` when this firing runs on the AlarmKit (Strategy A) backend — iOS
    /// 26+ with AlarmKit authorized (#383). On that path the SYSTEM owns the
    /// alarm sound (the in-app screen must not start its own `AudioService`) and
    /// a snooze re-fires as a real system alarm, so the firing screen DISMISSES
    /// after a snooze rather than running the in-place notification-snooze
    /// countdown (which is a Strategy-B-only affordance). Below iOS 26 this is
    /// `false` and the existing notification behaviour is unchanged.
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

    /// Wall-clock `Date` of the next ring after the current snooze — the FIXED
    /// `anchor` (the moment the user tapped «Поспать ещё», stored once in
    /// `snooze()`) shifted forward exactly one `snoozeMinutes` interval. This
    /// mirrors `AlarmScheduler.scheduledFireDate`, which arms the snooze trigger
    /// at `tap + snoozeMinutes` regardless of `snoozeCount`. Anchoring to the
    /// FIXED tap moment (not the per-tick clock and not the alarm's time-of-day ×
    /// snoozeCount) is what lets the live countdown decrement: the target is
    /// constant while `now` moves, so `secondsUntilNextRing(from:)` falls to `0`
    /// and the chrome tears down. A 07:00 alarm snoozed at 07:12 counts down to
    /// 07:17, not the long-past 07:05 (issue #396). The default `anchor`
    /// (`snoozeAnchor`, the stored tap moment) is used by production call sites;
    /// tests pin it explicitly. Returns `nil` before the first snooze.
    func nextRingDate(anchor: Date? = nil) -> Date? {
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
        // `chargeWithReceipt` surfaces the persisted charge transaction so a
        // later refund can link back to it via `refundsTransactionID` (issue
        // #366). Without that link the foreground refund offsets the balance
        // but the original charge still inflates snooze stats / streak, the
        // exact bug #133 fixed for the notification-action path only.
        guard let chargeTransaction = balanceService.chargeWithReceipt(
            amount: penalty,
            alarmID: alarm.id
        ) else { return false }

        snoozeCount += 1
        // Pin the tap moment ONCE so the live countdown target stays fixed while
        // `now` advances (issue #396). Mirrors the instant the scheduler arms the
        // trigger at (`scheduledFireDate(now: Date(), …)`) so the in-app countdown
        // and the real re-ring agree. Re-tapping snooze re-anchors to the new tap,
        // matching the freshly-armed trigger.
        snoozeAnchor = Date()
        scheduler.scheduleSnooze(for: alarm, snoozeCount: snoozeCount) { [weak self] result in
            self?.handleScheduleResult(
                result,
                penalty: penalty,
                chargeTransactionID: chargeTransaction.id,
                completion: scheduleCompletion
            )
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
