import CoreData
import Foundation

/// Responsible for CRUD operations on Transaction entities in Core Data
final class TransactionRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.context) {
        self.context = context
    }

    // MARK: - Fetch

    func fetchAll() -> [Transaction] {
        let request: NSFetchRequest<TransactionEntity> = TransactionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            return try context.fetch(request).compactMap { map($0) }
        } catch {
            print("Fetch transactions error: \(error)")
            return []
        }
    }

    func fetchCharges(since date: Date) -> [Transaction] {
        let request: NSFetchRequest<TransactionEntity> = TransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "type == %@ AND createdAt >= %@",
            TransactionType.charge.rawValue,
            date as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            return try context.fetch(request).compactMap { map($0) }
        } catch {
            print("Fetch charges error: \(error)")
            return []
        }
    }

    // MARK: - Create

    @discardableResult
    func record(_ transaction: Transaction) -> Bool {
        let entity = TransactionEntity(context: context)
        entity.id = transaction.id
        entity.type = transaction.type.rawValue
        entity.amount = transaction.amount
        entity.alarmID = transaction.alarmID
        entity.createdAt = transaction.createdAt
        PersistenceController.shared.save()
        return true
    }

    // MARK: - Streak calculation

    /// Returns count of consecutive days ending today with no charge transactions.
    func currentStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        let allCharges = fetchAll().filter { $0.type == .charge }
        let chargeDates = Set(allCharges.map { calendar.startOfDay(for: $0.createdAt) })

        // Walk backwards day by day
        while !chargeDates.contains(checkDate) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
            // Stop if we've gone back more than 365 days (reasonable limit)
            if streak > 365 { break }
        }

        return streak
    }

    // MARK: - Mapping

    private func map(_ entity: TransactionEntity) -> Transaction? {
        guard
            let id = entity.id,
            let typeRaw = entity.type,
            let type = TransactionType(rawValue: typeRaw),
            let createdAt = entity.createdAt
        else { return nil }

        return Transaction(
            id: id,
            type: type,
            amount: entity.amount,
            alarmID: entity.alarmID,
            createdAt: createdAt
        )
    }
}
