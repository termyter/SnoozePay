import Foundation

final class AlarmRepository {
    static let shared = AlarmRepository()
    private let key = "stored_alarms"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func fetchAll() -> [Alarm] {
        guard let data = defaults.data(forKey: key),
              let alarms = try? JSONDecoder().decode([Alarm].self, from: data)
        else { return [] }
        return alarms.sorted { $0.time < $1.time }
    }

    func fetch(id: UUID) -> Alarm? {
        fetchAll().first { $0.id == id }
    }

    @discardableResult
    func save(_ alarm: Alarm) -> Bool {
        var alarms = fetchAll()
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx] = alarm
        } else {
            alarms.append(alarm)
        }
        persist(alarms)

        AlarmScheduler.shared.cancel(alarm.id)
        if alarm.enabled {
            AlarmScheduler.shared.schedule(alarm)
        }
        return true
    }

    func delete(id: UUID) {
        var alarms = fetchAll()
        alarms.removeAll { $0.id == id }
        persist(alarms)
        AlarmScheduler.shared.cancel(id)
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard var alarm = fetch(id: id) else { return }
        alarm.enabled = enabled
        save(alarm)
    }

    private func persist(_ alarms: [Alarm]) {
        let data = try? JSONEncoder().encode(alarms)
        defaults.set(data, forKey: key)
    }
}
