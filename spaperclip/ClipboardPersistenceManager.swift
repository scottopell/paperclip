import AppKit
import CoreData
import Foundation
import OSLog

/// Manages the persistence of clipboard history items using Core Data
class ClipboardPersistenceManager {
    static let shared = ClipboardPersistenceManager()

    private let coreDataManager = CoreDataManager.shared
    private let logger = Logger(
        subsystem: "com.scottopell.spaperclip", category: "ClipboardPersistenceManager")

    private init() {}

    // MARK: - Save Operations

    /// Saves a clipboard history item to Core Data
    func saveHistoryItem(_ item: ClipboardHistoryItem) {
        coreDataManager.performBackgroundTask { context in
            self.logger.info("Saving clipboard history item to Core Data")

            // Create a new history item entity
            let historyItemEntity = CDClipboardHistoryItem(context: context)

            // Set basic attributes
            historyItemEntity.timestamp = item.timestamp

            // Create source application entity if available
            if let sourceApp = item.sourceApplication {
                let sourceAppEntity = CDSourceApplicationInfo(context: context)

                sourceAppEntity.bundleIdentifier = sourceApp.bundleIdentifier
                sourceAppEntity.applicationName = sourceApp.applicationName

                // Convert NSImage to Data for storage
                if let icon = sourceApp.applicationIcon, let tiffData = icon.tiffRepresentation {
                    sourceAppEntity.applicationIconData = tiffData
                }

                // Create relationship between history item and source app
                historyItemEntity.sourceApplication = sourceAppEntity
            }

            // Create clipboard content entities
            for content in item.contents {
                let contentEntity = CDClipboardContent(context: context)

                contentEntity.data = content.data
                contentEntity.descriptionText = content.description

                // Create format entities
                for format in content.formats {
                    let formatEntity = CDClipboardFormat(context: context)
                    formatEntity.uti = format.uti

                    // Add format to content's formats
                    contentEntity.addToFormats(formatEntity)
                }

                // Add content to history item's contents
                historyItemEntity.addToContents(contentEntity)
            }

            self.logger.info(
                "Clipboard history item saved with \(item.contents.count) content items")
        }
    }

    // MARK: - Load Operations

    /// Loads all clipboard history items from Core Data
    func loadHistoryItems(completion: @escaping ([ClipboardHistoryItem]) -> Void) {
        // Use the background context to avoid blocking the main thread for potentially large datasets
        self.logger.info("Starting to load history items...")

        coreDataManager.performBackgroundTask { context in
            let fetchRequest = NSFetchRequest<CDClipboardHistoryItem>(
                entityName: "CDClipboardHistoryItem")
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

            self.logger.info("Executing fetch request for history items")

            do {
                let historyItemEntities = try context.fetch(fetchRequest)
                self.logger.info("Fetched \(historyItemEntities.count) raw entities from Core Data")

                var historyItems: [ClipboardHistoryItem] = []

                for entity in historyItemEntities {
                    if let historyItem = self.convertToHistoryItem(from: entity) {
                        historyItems.append(historyItem)
                    }
                }

                self.logger.info(
                    "Successfully converted \(historyItems.count) history items from Core Data")

                // Return results on the main thread
                DispatchQueue.main.async {
                    self.logger.info(
                        "Delivering \(historyItems.count) history items to UI on main thread")
                    completion(historyItems)
                }
            } catch {
                self.logger.error("Failed to fetch history items: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }

    // MARK: - Conversion Methods

    /// Converts a Core Data entity to a ClipboardHistoryItem model
    private func convertToHistoryItem(from entity: CDClipboardHistoryItem) -> ClipboardHistoryItem?
    {
        // Convert contents
        var contents: [ClipboardContent] = []
        if let contentEntities = entity.contents as? Set<CDClipboardContent> {
            for contentEntity in contentEntities {
                if let content = convertToClipboardContent(from: contentEntity) {
                    contents.append(content)
                }
            }
        }

        // Convert source application info
        var sourceApp: SourceApplicationInfo? = nil
        if let sourceAppEntity = entity.sourceApplication {
            sourceApp = convertToSourceApplicationInfo(from: sourceAppEntity)
        }

        return ClipboardHistoryItem(
            timestamp: entity.timestamp ?? Date(),
            contents: contents,
            sourceApplication: sourceApp
        )
    }

    /// Converts a Core Data entity to a ClipboardContent model
    private func convertToClipboardContent(from entity: CDClipboardContent) -> ClipboardContent? {
        guard let data = entity.data,
            let description = entity.descriptionText
        else {
            logger.error("Missing required attributes for clipboard content")
            return nil
        }

        // Convert formats
        var formats: [ClipboardFormat] = []
        if let formatEntities = entity.formats as? Set<CDClipboardFormat> {
            for formatEntity in formatEntities {
                if let uti = formatEntity.uti {
                    formats.append(ClipboardFormat(uti: uti))
                }
            }
        }

        return ClipboardContent(
            data: data,
            formats: formats,
            description: description
        )
    }

    /// Converts a Core Data entity to a SourceApplicationInfo model
    private func convertToSourceApplicationInfo(from entity: CDSourceApplicationInfo)
        -> SourceApplicationInfo?
    {
        return SourceApplicationInfo(
            bundleIdentifier: entity.bundleIdentifier,
            applicationName: entity.applicationName,
            applicationIconData: entity.applicationIconData
        )
    }

    // MARK: - Management Operations

    /// Clears all history items
    func clearAllHistory() {
        coreDataManager.clearAllData()
    }

    /// Limits history size to specified number of items
    func limitHistorySize(to maxItems: Int) {
        coreDataManager.limitHistorySize(to: maxItems)
    }
}
