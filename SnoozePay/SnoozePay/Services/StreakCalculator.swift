import Foundation

/// Computes the «серия» — the run of consecutive days, ending today or
/// yesterday, on which the user actually exercised the habit (woke without a
/// charge). Extracted from `TransactionRepository.computeStreak` (#276) once
/// the definition had to consult `WakeEventStore` as well as the ledger; a
/// dedicated value type keeps the two inputs injectable and the maths unit
/// testable without touching either store's serial queue.
///
/// ## Semantics (#276, design SPMore4.jsx:113-123 / SPScreensV2.jsx:861-868)
///
/// The streak counts «дни без срыва с прорывом привычки» — days the user
/// genuinely got up. Walking backwards from today:
///
///   - **Wake day, no charge** → extends the streak (+1).
///   - **Charge day** → breaks the streak (stop, regardless of a wake).
///   - **Neutral day** (no wake *and* no charge — no alarm was scheduled, the
///     user was travelling, etc.) → SKIP: it neither extends nor breaks the
///     run. The design counts the habit, not the calendar, so a quiet weekend
///     shouldn't reset a 30-day streak; but it also can't claim credit for a
///     day the user never woke to an alarm.
///   - **Today before its wake is recorded** → neutral, so the number doesn't
///     optimistically count today until the alarm has actually fired and been
///     dismissed. (A charge today still breaks immediately.)
///
/// The walk starts at today and continues backwards while days remain neutral
/// or wake-positive; the first charge stops it. Because today and a still-
/// asleep "tomorrow morning" are neutral, an unbroken run that last logged a
/// wake *yesterday* still reads as a live streak.
///
/// ## Legacy fallback
///
/// `WakeEventStore` shipped after the original ledger (#235). Existing users
/// who built up a streak before wake events were recorded would see it
/// collapse to 0 the moment this stricter rule lands — every historical day is
/// "neutral" with no wake data, so nothing extends. To avoid punishing them,
/// when the wake store is **entirely empty** we fall back to the legacy
/// transaction-only heuristic (consecutive charge-free days back to the first
/// transaction). The moment a single real wake event exists we switch to the
/// accurate definition. New installs have no transactions either, so they
/// correctly start at 0.
enum StreakCalculator {

    /// - Parameters:
    ///   - transactions: the full ledger (charges + topups). Only `.charge`
    ///     entries break or bound the streak.
    ///   - wakeDays: `startOfDay` dates the user dismissed an alarm
    ///     (`WakeEventStore.wakeDays()`).
    ///   - now: injected for deterministic tests; defaults to the wall clock.
    ///   - calendar: injected so tests pin a fixed timezone/locale.
    static func currentStreak(
        transactions: [Transaction],
        wakeDays: Set<Date>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        // No wake history at all → degrade to the pre-#276 behaviour so
        // long-standing users don't see their streak vanish overnight.
        guard !wakeDays.isEmpty else {
            return legacyStreak(transactions: transactions, now: now, calendar: calendar)
        }

        // Exclude REFUNDED charges — a snooze charge that failed to schedule
        // is auto-refunded (its offsetting `.topup` carries
        // `refundsTransactionID`) and per design "doesn't count", so it must not
        // break the streak. The Statistics heatmap is already built from
        // `realCharges`; consulting the same helper here is what stops streak
        // and heatmap from contradicting each other (#439). `realCharges` is a
        // pure static function over the array — no store/queue access.
        let chargeDays = Set(
            TransactionRepository.realCharges(from: transactions)
                .map { calendar.startOfDay(for: $0.createdAt) }
        )

        var streak = 0
        var day = calendar.startOfDay(for: now)

        // Bound the walk so a user with a single ancient wake event doesn't
        // loop indefinitely over empty history. The wake store retains ~400
        // days, so anything older can't contribute a wake anyway.
        let earliest = calendar.date(byAdding: .day, value: -400, to: calendar.startOfDay(for: now))
            ?? calendar.startOfDay(for: now)

        while day >= earliest {
            if chargeDays.contains(day) {
                break              // a slip ends the run immediately.
            }
            if wakeDays.contains(day) {
                streak += 1        // genuine wake without a charge.
            }
            // else: neutral day (incl. today before its wake) — skip, don't break.
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return streak
    }

    /// Pre-#276 definition: consecutive charge-free calendar days from today
    /// back to the first recorded transaction. Retained only as the empty-
    /// wake-store fallback so historical streaks survive the upgrade.
    private static func legacyStreak(
        transactions: [Transaction],
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard !transactions.isEmpty else { return 0 }

        var streak = 0
        var checkDate = calendar.startOfDay(for: now)
        // Same refunded-charge exclusion as the accurate path (#439) so the
        // legacy fallback can't reset a streak on a refunded snooze either.
        let chargeDates = Set(
            TransactionRepository.realCharges(from: transactions)
                .map { calendar.startOfDay(for: $0.createdAt) }
        )
        let firstTransactionDate = calendar.startOfDay(
            for: transactions.map { $0.createdAt }.min() ?? now
        )

        while !chargeDates.contains(checkDate) && checkDate >= firstTransactionDate {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
        }

        return streak
    }
}
