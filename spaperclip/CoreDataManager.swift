import CoreData
import Foundation
import OSLog

/// Manages Core Data operations for clipboard history persistence
class CoreDataManager {
    static let shared = CoreDataManager()

    private let logger = Logger(subsystem: "com.scottopell.spaperclip", category: "CoreDataManager")

    // MARK: - Core Data stack

    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "sPaperclipDataModel")

        // Create a proper URL for the database file in Application Support directory
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let storeURL = appSupportURL.appendingPathComponent("spaperclip").appendingPathComponent(
            "clipboard.sqlite")

        // Create directory if it doesn't exist
        let storeDirectory = storeURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: storeDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: storeDirectory, withIntermediateDirectories: true)
                self.logger.info("Created directory for database at: \(storeDirectory.path)")
            } catch {
                self.logger.error(
                    "Failed to create directory for database: \(error.localizedDescription)")
            }
        }

        // Configure the store to allow external storage for binary data
        let storeDescription = NSPersistentStoreDescription(url: storeURL)
        storeDescription.setOption(
            true as NSNumber, forKey: "NSPersistentStoreAllowExternalBinaryDataStorageOption")
        storeDescription.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [storeDescription]

        self.logger.info("Setting up persistent store at: \(storeURL.path)")

        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                self.logger.error("Failed to load persistent stores: \(error.localizedDescription)")
                fatalError("Failed to load persistent stores: \(error)")
            }

            self.logger.info(
                "Successfully loaded persistent store: \(storeDescription.url?.absoluteString ?? "unknown")"
            )
        }

        // Merge policies to handle conflicts
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    // Background context for write operations
    private lazy var backgroundContext: NSManagedObjectContext = {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()

    // View context for read operations
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    private init() {}

    // MARK: - Core Data operations

    /// Performs a block on the background context and saves changes
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundContext.perform {
            block(self.backgroundContext)

            if self.backgroundContext.hasChanges {
                do {
                    try self.backgroundContext.save()
                    self.logger.info("Background context saved successfully")
                } catch {
                    self.logger.error(
                        "Failed to save background context: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Saves the view context
    func saveViewContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
                logger.info("View context saved successfully")
            } catch {
                logger.error("Failed to save view context: \(error.localizedDescription)")
            }
        }
    }

    /// Clears all clipboard history data
    func clearAllData() {
        performBackgroundTask { context in
            // Delete all history items (cascading deletion will handle related entities)
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(
                entityName: "CDClipboardHistoryItem")
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

            do {
                try context.execute(deleteRequest)
                self.logger.info("All clipboard history data cleared")
            } catch {
                self.logger.error(
                    "Failed to clear clipboard history data: \(error.localizedDescription)")
            }
        }
    }

    /// Limits the history to a specified number of items by removing oldest entries
    func limitHistorySize(to maxItems: Int) {
        performBackgroundTask { context in
            let fetchRequest = NSFetchRequest<CDClipboardHistoryItem>(
                entityName: "CDClipboardHistoryItem")
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

            do {
                let allItems = try context.fetch(fetchRequest)
                if allItems.count > maxItems {
                    let itemsToDelete = allItems[maxItems..<allItems.count]
                    for item in itemsToDelete {
                        context.delete(item)
                    }
                    self.logger.info("Removed \(itemsToDelete.count) old history items")
                }
            } catch {
                self.logger.error("Failed to limit history size: \(error.localizedDescription)")
            }
        }
    }
}
