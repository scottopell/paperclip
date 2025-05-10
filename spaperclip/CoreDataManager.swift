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
    // TODO: implement an algorithm that balances age and size
    // TODO: support history limit in terms of size (bytes), size (number of items), age (days)
    // Ideally I can tune this to prune individual items based on their contents,
    // for example, consider the default macos screenshot, it puts both tiff and png on the clipboard
    // but tiff is obviously much larger (bytes) and the PNG is sufficient for 99.9% of use cases
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

    // MARK: - Debugging and Statistics

    /// Represents Core Data store statistics
    struct StoreStatistics {
        let storeLocation: String
        let storeSizeBytes: Int64
        let binaryDataSizeBytes: Int64
        let totalItems: Int
        let oldestItemDate: Date?
        let newestItemDate: Date?
        let modelName: String?
        let metadata: [String: Any]
        let debugInfo: String  // Additional debugging info

        /// Format a byte size as a mebibyte string
        func formatSize(_ byteSize: Int64) -> String {
            let mebibytes = Double(byteSize) / 1_048_576.0  // Use 2^20 for MiB
            return String(format: "%.2f", mebibytes)
        }
    }

    /// Returns comprehensive statistics about the Core Data store
    func getStoreStatistics() -> StoreStatistics {
        var storeLocation = "Unknown"
        var storeSize: Int64 = 0
        var totalItems = 0
        var oldestItemDate: Date? = nil
        var newestItemDate: Date? = nil
        var modelName: String? = nil
        var metadata: [String: Any] = [:]
        var debugInfo = ""

        // Get total items
        let fetchRequest = NSFetchRequest<CDClipboardHistoryItem>(
            entityName: "CDClipboardHistoryItem")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            // Get item count and dates
            totalItems = try viewContext.count(for: fetchRequest)

            // Detailed query to inspect actual data sizes
            debugInfo += "--- CONTENT SIZE BREAKDOWN ---\n"
            let items = try viewContext.fetch(fetchRequest)
            newestItemDate = items.first?.timestamp
            oldestItemDate = items.last?.timestamp

            // Calculate total size of binary data in memory
            var totalBinaryDataSize: Int64 = 0
            var contentCounter = 0

            for (index, item) in items.enumerated() {
                let contents = item.contents?.allObjects as? [CDClipboardContent] ?? []
                debugInfo += "Item \(index): \(contents.count) content objects\n"

                for (cIndex, content) in contents.enumerated() {
                    contentCounter += 1

                    let dataSize = Int64(content.data?.count ?? 0)
                    totalBinaryDataSize += dataSize

                    // Get the format information
                    let formats = content.formats?.allObjects as? [CDClipboardFormat] ?? []
                    let formatTypes = formats.compactMap { $0.uti }.joined(separator: ", ")

                    debugInfo += "  - Content \(cIndex): \(dataSize) bytes (\(formatTypes))\n"

                    // Sample a few files to check if they match expected size
                    if formats.contains(where: { ($0.uti ?? "").contains("tiff") })
                        && dataSize > 100000
                    {
                        debugInfo +=
                            "    TIFF detected: \(ByteCountFormatter.string(fromByteCount: dataSize, countStyle: .file))\n"
                    }
                }
            }

            debugInfo +=
                "Total inspected: \(contentCounter) content objects across \(min(items.count, 5)) items\n"
            debugInfo +=
                "Total binary data in memory: \(ByteCountFormatter.string(fromByteCount: totalBinaryDataSize, countStyle: .file))\n\n"

            // Get store metadata
            if let store = persistentContainer.persistentStoreCoordinator.persistentStores.first,
                let storeURL = store.url
            {
                storeLocation = storeURL.path
                debugInfo += "--- STORAGE LOCATION DETAILS ---\n"
                debugInfo += "Main DB path: \(storeURL.path)\n"

                // Check all related database files (WAL, SHM, etc)
                let storeDirectory = storeURL.deletingLastPathComponent()
                let storeName = storeURL.lastPathComponent
                debugInfo += "Storage directory: \(storeDirectory.path)\n"

                do {
                    let directoryContents = try FileManager.default.contentsOfDirectory(
                        at: storeDirectory,
                        includingPropertiesForKeys: [.fileSizeKey],
                        options: [.skipsHiddenFiles])

                    debugInfo += "All files in store directory:\n"
                    var mainDBSize: Int64 = 0
                    var allRelatedFilesSize: Int64 = 0

                    for fileURL in directoryContents {
                        if fileURL.lastPathComponent.hasPrefix(
                            storeURL.deletingPathExtension().lastPathComponent)
                        {
                            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                            let fileSize = Int64(resourceValues.fileSize ?? 0)

                            debugInfo +=
                                "  - \(fileURL.lastPathComponent): \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))\n"

                            if fileURL.lastPathComponent == storeName {
                                mainDBSize = fileSize
                            }

                            if fileURL.lastPathComponent.hasSuffix(".sqlite")
                                || fileURL.lastPathComponent.hasSuffix(".sqlite-wal")
                                || fileURL.lastPathComponent.hasSuffix(".sqlite-shm")
                            {
                                allRelatedFilesSize += fileSize
                            }
                        }
                    }

                    debugInfo +=
                        "Main DB size (just the .sqlite file): \(ByteCountFormatter.string(fromByteCount: mainDBSize, countStyle: .file))\n"
                    debugInfo +=
                        "All related SQLite files size: \(ByteCountFormatter.string(fromByteCount: allRelatedFilesSize, countStyle: .file))\n\n"

                    // Set the main database size in bytes
                    let fileAttributes = try FileManager.default.attributesOfItem(
                        atPath: storeURL.path)
                    storeSize = fileAttributes[.size] as? Int64 ?? 0
                } catch {
                    debugInfo += "Error listing directory contents: \(error.localizedDescription)\n"
                }

                // Get additional metadata
                metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                    ofType: store.type, at: storeURL, options: nil)

                if let modelHashes = metadata["NSStoreModelVersionHashes"] as? [String: Any],
                    let firstModelName = modelHashes.keys.first
                {
                    modelName = firstModelName
                }
            }

            let stats = StoreStatistics(
                storeLocation: storeLocation,
                storeSizeBytes: storeSize,
                binaryDataSizeBytes: totalBinaryDataSize,
                totalItems: totalItems,
                oldestItemDate: oldestItemDate,
                newestItemDate: newestItemDate,
                modelName: modelName,
                metadata: metadata,
                debugInfo: debugInfo
            )

            // Log statistics to console
            logger.info(
                """
                Core Data Store Statistics:
                - Store Location: \(storeLocation)
                - Main DB Size: \(stats.formatSize(storeSize)) MiB
                - Binary Data Size: \(stats.formatSize(totalBinaryDataSize)) MiB
                - Total Items: \(totalItems)
                - Oldest Item: \(oldestItemDate?.description ?? "N/A")
                - Newest Item: \(newestItemDate?.description ?? "N/A")
                """)
            logger.info("Debug Info: \(debugInfo)")

            return stats

        } catch {
            logger.error("Failed to get store statistics: \(error.localizedDescription)")
            debugInfo += "Error during statistics collection: \(error.localizedDescription)\n"

            return StoreStatistics(
                storeLocation: storeLocation,
                storeSizeBytes: storeSize,
                binaryDataSizeBytes: 0,
                totalItems: totalItems,
                oldestItemDate: oldestItemDate,
                newestItemDate: newestItemDate,
                modelName: modelName,
                metadata: metadata,
                debugInfo: debugInfo
            )
        }
    }

}
