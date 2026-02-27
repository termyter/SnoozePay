import CoreData

/// Singleton Core Data stack
final class PersistenceController {

    static let shared = PersistenceController()

    let container: NSPersistentContainer

    var context: NSManagedObjectContext { container.viewContext }

    private init() {
        container = NSPersistentContainer(name: "SnoozePay")
        container.loadPersistentStores { _, error in
            if let error {
                // In production, handle migration errors gracefully
                fatalError("Core Data store failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Log but don't crash on save errors
            print("Core Data save error: \(error)")
        }
    }
}
