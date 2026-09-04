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

    /// UserDefaults key holding the JSON-encoded `[Date]` of wake days
    /// (each normalised to `startOfDay`).
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

    // MARK: - Write

    /// Records that the user woke up (dismissed an alarm) on the given date.
    /// Stored per calendar day — repeat dismissals on the same day dedupe,
    /// so the persisted timestamp is the *first* dismissal of that morning
    /// (the actual "подъём"; later dismissals are naps / other alarms).
    ///
    /// Callers keep passing a plain `Date` — the exact instant is captured
    /// here, which is why no firing-flow call site had to change for #348.
    func recordWake(on date: Date = Date(), calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        queue.sync {
            var days = readAll()
            guard !days.contains(day) else { return }
            days.insert(day)

            var times = readAllTimes()
            times.append(date)

            // Prune anything beyond the retention window so the blob stays
            // bounded. Pruning keys off "now", not the recorded date, so a
            // backdated test fixture can still round-trip recent history.
            if let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: Date()) {
                let cutoffDay = calendar.startOfDay(for: cutoff)
                days = days.filter { $0 >= cutoffDay }
                times = times.filter { $0 >= cutoffDay }
            }
            persist(days)
            persistTimes(times)
        }
    }

    // MARK: - Read

    /// All recorded wake days as `startOfDay` dates. Decode failures collapse
    /// to an empty set — wake days are a display-only signal (heatmap "встал
    /// сразу" cells), so the corrupt-blob ceremony of the financial ledger
    /// would be overkill here; the heatmap degrades to "не было будильника".
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
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return Set(try JSONDecoder().decode([Date].self, from: data))
        } catch {
            os_log(
                "Decode failed, wake history degrades to empty: %{public}@",
                log: Self.log, type: .error, String(describing: error)
            )
            return []
        }
    }

    private func readAllTimes() -> [Date] {
        guard let data = defaults.data(forKey: timesKey) else { return [] }
        do {
            return try JSONDecoder().decode([Date].self, from: data)
        } catch {
            os_log(
                "Decode failed, wake times degrade to empty: %{public}@",
                log: Self.log, type: .error, String(describing: error)
            )
            return []
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
