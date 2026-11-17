import Foundation
import os

/// Persists the calendar days on which the user actually got up — i.e.
/// dismissed a firing alarm (either from the in-app firing screen or the
/// "Выключить" notification action).
///
/// The behavioural statistics screen (#235) needs to distinguish three day
/// states on the heatmap: "встал сразу" (alarm fired, zero snoozes), "snoozed
/// N times" (charge transactions exist), and "не было будильника" (no data).
/// Charges already live in `TransactionRepository`; this store supplies the
/// missing "alarm fired and was dismissed" signal. Days recorded before this
/// store shipped simply render as "не было будильника" — the issue explicitly
/// allows the dark fallback for missing data.
///
/// Storage follows the repository convention: UserDefaults + Codable, with a
/// serial queue guarding read-modify-write cycles (an in-app dismiss and a
/// notification-action dismiss can race).
final class WakeEventStore {

    static let shared = WakeEventStore()

    /// UserDefaults key holding the JSON-encoded `[Date]` of wake days.
    ///
    /// Since #1064 each row is the canonical UTC midnight of the local civil
    /// day the user woke on (``WakeDayIdentity/canonicalStoredDay``), not a
    /// `startOfDay` in whatever zone the device happened to report. Rows
    /// written before that change remain raw `startOfDay` instants; readers
    /// resolve both through ``WakeDayIdentity(storedDay:)``, whose docstring
    /// explains how a legacy value's writing offset is recovered from the
    /// instant itself. Keeping the blob a `[Date]` preserved the sorting; the
    /// 400-day prune now compares civil identities so the window does not
    /// shift by a day for readers west of UTC. The exact instants stay in
    /// `wake_times`.
    private let key = "wake_days"

    /// UserDefaults key holding the JSON-encoded `[Date]` of the *exact*
    /// wake instants — one per calendar day, the first dismissal of that
    /// morning (#348, "ВРЕМЯ ПОДЪЁМА" card).
    ///
    /// Written alongside `wake_days` rather than replacing it: the heatmap
    /// and the streak only ever ask "did the user get up that day", and
    /// re-deriving days from timestamps would break every install that
    /// recorded wakes before this key existed. Days written before #348
    /// simply carry no timestamp, so the wake-time card ignores them.
    private let timesKey = "wake_times"

    /// Days older than this are pruned on write — the statistics screen only
    /// ever looks back a few months, and an unbounded array would grow by one
    /// entry per morning forever.
    private static let retentionDays = 400

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.snoozepay.wakedays.serial")
    private static let log = OSLog(
        subsystem: AppLogger.subsystem,
        category: "WakeEventStore"
    )

    /// Production code MUST use `WakeEventStore.shared`. The internal
    /// initializer exists so tests can inject an isolated `UserDefaults`
    /// suite — same pattern as `TransactionRepository`.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private convenience init() {
        self.init(defaults: .standard)
    }

    enum ReadResult: Equatable {
        case missing
        case value([Date])
        case unreadable

        var dates: [Date]? {
            switch self {
            case .missing: return []
            case .value(let dates): return dates
            case .unreadable: return nil
            }
        }

        var isUnreadable: Bool { self == .unreadable }
    }

    struct Snapshot: Equatable {
        let days: ReadResult
        let times: ReadResult
    }

    /// One read boundary for statistics; a missing legacy timestamp key is
    /// healthy, while a damaged key remains distinguishable from no history.
    func readSnapshot() -> Snapshot {
        queue.sync { Snapshot(days: readResult(forKey: key), times: readResult(forKey: timesKey)) }
    }

    // MARK: - Write

    /// Records that the user woke up (dismissed an alarm) on the given date.
    /// Stored per calendar day — repeat dismissals on the same day dedupe,
    /// so the persisted timestamp is the *first* dismissal of that morning
    /// (the actual "подъём"; later dismissals are naps / other alarms).
    ///
    /// Callers keep passing a plain `Date`; `calendar` defaults to the
    /// device's current one and supplies the timezone the civil day is read
    /// in — never the calendar system (see ``WakeDayIdentity``). The exact
    /// instant is captured here, which is why no firing-flow call site had to
    /// change for #348. What changed in #1064 is the *day* row: it is written
    /// as the canonical UTC midnight of that day, so later reads no longer
    /// depend on the device's timezone.
    func recordWake(on date: Date = Date(), calendar: Calendar = .current) {
        let identity = WakeDayIdentity(date: date, calendar: calendar)
        guard let day = identity.canonicalStoredDay else {
            // Unreachable for any Gregorian date. Logged rather than asserted so
            // a future calendar change cannot silently swallow a morning.
            os_log("[WAKE-1064-CANONICAL] could not build %{public}@ — wake not recorded",
                   log: Self.log, type: .error, identity.description)
            return
        }
        queue.sync {
            // An unreadable key is left exactly as it is (#1097). Writing
            // today's row over it would erase the damaged history and, worse,
            // turn the "history unavailable" state #669 surfaces into what
            // looks like a fresh install after the very next dismissal. The
            // readable sibling key still records normally.
            guard let storedDays = readResult(forKey: key).dates else {
                logSkippedWrite(forKey: key)
                recordInstant(date, identity: identity, calendar: calendar)
                return
            }
            var days = Set(storedDays)
            // The row is already present for *this* day — a repeat dismissal,
            // or a canonical row written earlier today. Deliberately not an
            // identity match: a pre-#1064 row can reconstruct to a displaced
            // day (the ambiguous 10:00–12:00 window), and treating it as
            // "already recorded" would swallow this morning's canonical row
            // and its exact instant. Two rows for one civil day are harmless —
            // every reader keys on the identity set — a dropped wake is not.
            guard !days.contains(day) else { return }
            days.insert(day)

            // Prune anything beyond the retention window so the blob stays
            // bounded. Pruning keys off "now", not the recorded date, so a
            // backdated test fixture can still round-trip recent history.
            //
            // Days compare by civil identity rather than instant: canonical
            // rows are UTC midnights, so comparing them to a local cutoff
            // would shift the window by up to a day for readers west of UTC.
            if let cutoffDay = retentionCutoffDay(calendar: calendar) {
                let cutoffIdentity = WakeDayIdentity(date: cutoffDay, calendar: calendar)
                days = days.filter { WakeDayIdentity(storedDay: $0) >= cutoffIdentity }
            }
            persist(days)
            recordInstant(date, identity: identity, calendar: calendar)
        }
    }

    /// Appends this morning's exact instant to `wake_times` unless the key is
    /// unreadable (left untouched, #1097) or already holds one for this day.
    /// Must be called inside `queue.sync`.
    private func recordInstant(_ date: Date, identity: WakeDayIdentity, calendar: Calendar) {
        guard var times = readResult(forKey: timesKey).dates else {
            logSkippedWrite(forKey: timesKey)
            return
        }
        // Keep "one instant per morning": a pre-#1064 row can already
        // carry this day's first dismissal (the day and the instant were
        // written together since #348), and appending this later one would
        // make `wakeTimes()` report two rows for one morning. The card
        // takes the earliest per day, so the UI hid it — the contract did
        // not.
        let hasInstantForMorning = times.contains {
            WakeDayIdentity(date: $0, calendar: calendar) == identity
        }
        guard !hasInstantForMorning else { return }
        times.append(date)
        // `wake_times` keeps the instant comparison — it is raw history,
        // and a one-day boundary nuance there costs nothing displayed.
        if let cutoffDay = retentionCutoffDay(calendar: calendar) {
            times = times.filter { $0 >= cutoffDay }
        }
        persistTimes(times)
    }

    private func retentionCutoffDay(calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: -Self.retentionDays, to: Date())
            .map { calendar.startOfDay(for: $0) }
    }

    private func logSkippedWrite(forKey storageKey: String) {
        os_log("[WAKE-669-UNREADABLE] %{public}@: wake not written, damaged history preserved",
               log: Self.log, type: .error, storageKey)
    }

    // MARK: - Read

    /// Compatibility read for existing callers. Statistics uses the typed
    /// snapshot so an unreadable history cannot masquerade as a fresh install.
    ///
    /// Values are the stored day rows — canonical UTC midnights for rows
    /// written since #1064, raw `startOfDay`s for older ones. Consumers that
    /// need to answer "was the user awake on *this* day" must compare through
    /// ``WakeDayIdentity`` rather than these instants.
    func wakeDays() -> Set<Date> {
        queue.sync { readAll() }
    }

    /// Exact wake instants, ascending, one per recorded morning (#348).
    /// Empty for installs that only ever wrote the legacy day-granular blob —
    /// the "ВРЕМЯ ПОДЪЁМА" card then honestly renders nothing rather than
    /// inventing a time from a bare calendar day.
    func wakeTimes() -> [Date] {
        queue.sync { readAllTimes().sorted() }
    }

    // MARK: - Private (must be called inside queue.sync)

    private func readAll() -> Set<Date> {
        Set(readResult(forKey: key).dates ?? [])
    }

    private func readAllTimes() -> [Date] {
        readResult(forKey: timesKey).dates ?? []
    }

    private func readResult(forKey storageKey: String) -> ReadResult {
        guard let raw = defaults.object(forKey: storageKey) else { return .missing }
        guard let data = raw as? Data else {
            os_log("[WAKE-669-UNREADABLE] %{public}@: stored value is not Data",
                   log: Self.log, type: .error, storageKey)
            return .unreadable
        }
        do {
            return .value(try JSONDecoder().decode([Date].self, from: data).sorted())
        } catch {
            os_log("[WAKE-669-UNREADABLE] %{public}@: %{public}@",
                   log: Self.log, type: .error, storageKey, String(describing: error))
            return .unreadable
        }
    }

    private func persistTimes(_ times: [Date]) {
        do {
            let data = try JSONEncoder().encode(times.sorted())
            defaults.set(data, forKey: timesKey)
        } catch {
            // Same policy as `persist(_:)` — keep the previous blob rather
            // than erasing legitimate history on a transient encode failure.
            os_log(
                "Encode failed, previous wake times preserved: %{public}@",
                log: Self.log, type: .error, String(describing: error)
            )
        }
    }

    private func persist(_ days: Set<Date>) {
        do {
            let data = try JSONEncoder().encode(days.sorted())
            defaults.set(data, forKey: key)
        } catch {
            // Keep the previous blob — losing older wake days to a transient
            // encode failure would erase legitimate green heatmap cells.
            os_log(
                "Encode failed, previous wake history preserved: %{public}@",
                log: Self.log, type: .error, String(describing: error)
            )
        }
    }
}
