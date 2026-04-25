import Foundation

/// Persists alarms in UserDefaults with a serial queue protecting all reads and writes.
/// Without serialization, concurrent callers (UI edits + notification action handlers)
/// can race on read-modify-write cycles and lose updates — last writer wins.
final class AlarmRepository {

    static let shared = AlarmRepository()

    private let key = "stored_alarms"
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.snoozepay.alarms.serial")

    /// Production code MUST use `AlarmRepository.shared`.
    /// Direct construction creates an isolated instance with its own serial queue —
    /// two such instances racing on the same UserDefaults key reintroduce the race
    /// this class exists to prevent.
    #if DEBUG
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    #else
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    #endif

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

    func setEnabled(_ enabled: Bool, id: UUID) {
        let updated: Alarm? = queue.sync {
            var alarms = readAll()
            guard let idx = alarms.firstIndex(where: { $0.id == id }) else { return nil }
            alarms[idx].enabled = enabled
            persist(alarms)
            return alarms[idx]
        }

        guard let alarm = updated else { return }
        AlarmScheduler.shared.cancel(alarm.id)
        if alarm.enabled {
            AlarmScheduler.shared.schedule(alarm)
        }
    }

    // MARK: - Private (must be called inside queue.sync)

    private func readAll() -> [Alarm] {
        guard let data = defaults.data(forKey: key),
              let alarms = try? JSONDecoder().decode([Alarm].self, from: data)
        else { return [] }
        return alarms.sorted { $0.time < $1.time }
    }

    private func persist(_ alarms: [Alarm]) {
        do {
            let data = try JSONEncoder().encode(alarms)
            defaults.set(data, forKey: key)
        } catch {
            // Don't write nil — that wipes the entire alarm list silently.
            // Issue #23 tracks proper logging+UI surfacing; this guard at least preserves data.
            assertionFailure("AlarmRepository encode failed: \(error)")
            print("[AlarmRepository] encode failed, preserving previous state: \(error)")
        }
    }
}
