import CoreData
import Foundation

/// Responsible for CRUD operations on Alarm entities in Core Data
final class AlarmRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.context) {
        self.context = context
    }

    // MARK: - Fetch

    func fetchAll() -> [Alarm] {
        let request: NSFetchRequest<AlarmEntity> = AlarmEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "time", ascending: true)]
        do {
            return try context.fetch(request).map { map($0) }
        } catch {
            print("Fetch alarms error: \(error)")
            return []
        }
    }

    func fetch(id: UUID) -> Alarm? {
        let request: NSFetchRequest<AlarmEntity> = AlarmEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request).first).map { map($0) }
    }

    // MARK: - Create / Update

    @discardableResult
    func save(_ alarm: Alarm) -> Bool {
        // Upsert: find existing or create new
        let entity = findOrCreate(id: alarm.id)
        apply(alarm, to: entity)
        PersistenceController.shared.save()

        // Reschedule notifications
        AlarmScheduler.shared.cancel(alarm.id)
        if alarm.enabled {
            AlarmScheduler.shared.schedule(alarm)
        }

        return true
    }

    // MARK: - Delete

    func delete(id: UUID) {
        let request: NSFetchRequest<AlarmEntity> = AlarmEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        context.delete(entity)
        PersistenceController.shared.save()
        AlarmScheduler.shared.cancel(id)
    }

    // MARK: - Enable / Disable

    func setEnabled(_ enabled: Bool, id: UUID) {
        let request: NSFetchRequest<AlarmEntity> = AlarmEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.enabled = enabled
        PersistenceController.shared.save()

        // Update scheduled notifications
        AlarmScheduler.shared.cancel(id)
        if enabled, let alarm = fetch(id: id) {
            AlarmScheduler.shared.schedule(alarm)
        }
    }

    // MARK: - Mapping helpers

    private func map(_ entity: AlarmEntity) -> Alarm {
        Alarm(
            id: entity.id ?? UUID(),
            time: entity.time ?? Date(),
            repeatDays: entity.repeatDays ?? [],
            name: entity.name ?? "Будильник",
            soundID: entity.soundID ?? "default",
            vibrationEnabled: entity.vibrationEnabled,
            snoozeMinutes: Int(entity.snoozeMinutes),
            penaltyAmount: entity.penaltyAmount,
            progressiveScale: entity.progressiveScale,
            enabled: entity.enabled
        )
    }

    private func apply(_ alarm: Alarm, to entity: AlarmEntity) {
        entity.id = alarm.id
        entity.time = alarm.time
        entity.repeatDays = alarm.repeatDays
        entity.name = alarm.name
        entity.soundID = alarm.soundID
        entity.vibrationEnabled = alarm.vibrationEnabled
        entity.snoozeMinutes = Int16(alarm.snoozeMinutes)
        entity.penaltyAmount = alarm.penaltyAmount
        entity.progressiveScale = alarm.progressiveScale
        entity.enabled = alarm.enabled
    }

    private func findOrCreate(id: UUID) -> AlarmEntity {
        let request: NSFetchRequest<AlarmEntity> = AlarmEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first {
            return existing
        }
        return AlarmEntity(context: context)
    }
}
