import Foundation
import os.log

/// Persists alarms in UserDefaults with a serial queue protecting all reads and writes.
/// Without serialization, concurrent callers (UI edits + notification action handlers)
/// can race on read-modify-write cycles and lose updates — last writer wins.
final class AlarmRepository {

    static let shared = AlarmRepository()

    private let key = "stored_alarms"
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.snoozepay.alarms.serial")
    private static let log = OSLog(subsystem: "Ivan-Emelyanov.SnoozePay", category: "AlarmRepository")

    /// Production code MUST use `AlarmRepository.shared` to avoid creating
    /// isolated instances with separate serial queues (which reintroduces the
    /// race this class exists to prevent).
    ///
    /// Tests inject a custom `UserDefaults` suite to stay isolated from app
    /// state — that's why this initializer is `internal` rather than `private`.
    /// Production call sites that pass no arguments would create an isolated
    /// instance backed by `.standard`, defeating the singleton serialization,
    /// so we deliberately omit the default value: callers must be explicit.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private convenience init() {
        self.init(defaults: .standard)
    }

    // MARK: - Read

    func fetchAll() -> [Alarm] {
        queue.sync { readAll() }
    }

    func fetch(id: UUID) -> Alarm? {
        queue.sync { readAll().first { $0.id == id } }
    }

    // MARK: - Mutate

    @discardableResult
    func save(_ alarm: Alarm) -> Bool {
        queue.sync {
            var alarms = readAll()
            if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
                alarms[idx] = alarm
            } else {
                alarms.append(alarm)
            }
            persist(alarms)
        }

        AlarmScheduler.shared.cancel(alarm.id)
        if alarm.enabled {
            AlarmScheduler.shared.schedule(alarm)
        }
        return true
    }

    func delete(id: UUID) {
        queue.sync {
            var alarms = readAll()
            alarms.removeAll { $0.id == id }
            persist(alarms)
        }
        AlarmScheduler.shared.cancel(id)
    }

    /// Toggles `enabled` on the alarm with the given id.
    /// - Returns: `true` if the alarm existed and was updated; `false` if no alarm
    ///   matched the id. Callers (e.g. `AlarmsListViewModel`) rely on the boolean
    ///   to roll back optimistic UI flips when the underlying alarm has been
    ///   deleted from another path (issue #35).
    @discardableResult
    func setEnabled(_ enabled: Bool, id: UUID) -> Bool {
        let updated: Alarm? = queue.sync {
            var alarms = readAll()
            guard let idx = alarms.firstIndex(where: { $0.id == id }) else { return nil }
            alarms[idx].enabled = enabled
            persist(alarms)
            return alarms[idx]
        }

        guard let alarm = updated else {
            os_log(
                "setEnabled: no alarm with id %{public}@",
                log: Self.log, type: .info, id.uuidString
            )
            return false
        }
        AlarmScheduler.shared.cancel(alarm.id)
        if alarm.enabled {
            AlarmScheduler.shared.schedule(alarm)
        }
        return true
    }

    // MARK: - Private (must be called inside queue.sync)

    /// Returns persisted alarms.
    ///
    /// Differentiates three states (issue #23):
    ///   1. Key absent — new user, returns `[]` (legitimate empty state).
    ///   2. Key present, decode succeeds — returns sorted alarms.
    ///   3. Key present, decode fails — logs the error and returns `[]` for this read,
    ///      but the corrupted JSON stays on disk untouched. The next `persist()`
    ///      from a healthy in-memory state will overwrite it. Until then, the raw
    ///      bytes remain available for debugging instead of being silently wiped.
    private func readAll() -> [Alarm] {
        guard let data = defaults.data(forKey: key) else {
            // Case 1: brand-new install — no stored alarms yet.
            return []
        }
        do {
            let alarms = try JSONDecoder().decode([Alarm].self, from: data)
            return alarms.sorted { $0.time < $1.time }
        } catch {
            // Case 3: stored bytes can't be decoded. Surface the failure but DO NOT
            // overwrite the corrupted blob — preserve it for diagnosis.
            os_log(
                "Decode failed (%{public}d bytes preserved on disk): %{public}@",
                log: Self.log, type: .error, data.count, String(describing: error)
            )
            return []
        }
    }

    private func persist(_ alarms: [Alarm]) {
        do {
            let data = try JSONEncoder().encode(alarms)
            defaults.set(data, forKey: key)
        } catch {
            // Don't write nil — that wipes the entire alarm list silently.
            // If encode fails the previous JSON on disk stays intact (issue #23).
            os_log(
                "Encode failed, previous state preserved on disk: %{public}@",
                log: Self.log, type: .error, String(describing: error)
            )
            assertionFailure("AlarmRepository encode failed: \(error)")
        }
    }
}
