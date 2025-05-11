//
//  ClipboardMonitor.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

/*
 FUTURE IMPROVEMENT: Core Data Persistence

 Consider implementing Core Data for clipboard history persistence:

 1. [DONE] Binary Data Storage:
    - Use external storage option for large binary data
    - Configure: NSPersistentStoreAllowExternalBinaryDataStorageOption = true

 2. Performance Optimizations:
    - [DONE]Save clipboard data on background context
    - [????] Use fault objects to load binary data on-demand
    - [????]Set up fetch request templates with proper indexing

 3. Implementation Strategy:
    - Store metadata separately from binary content
    - Load binary content only when viewed
    - Release memory when content scrolls off-screen
    - Implement batch cleanup for older entries

 This approach would reduce memory usage and provide persistent
 clipboard history across app restarts.
 */

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os

// MARK: - Models

/// Represents a clipboard data format with its associated UTI (Uniform Type Identifier)
struct ClipboardFormat: Identifiable, Hashable {
    let id = UUID()
    let uti: String

    /// Provides a human-readable name for the format based on its UTI
    var typeName: String {
        switch uti {
        case UTType.plainText.identifier, "public.utf8-plain-text":
            return "Plain Text"
        case UTType.rtf.identifier, "public.rtf":
            return "Rich Text"
        case UTType.html.identifier, "public.html":
            return "HTML"
        case UTType.png.identifier, "public.png":
            return "PNG Image"
        case UTType.jpeg.identifier, "public.jpeg":
            return "JPEG Image"
        case UTType.tiff.identifier, "public.tiff":
            return "TIFF Image"
        case UTType.pdf.identifier, "com.adobe.pdf":
            return "PDF"
        case UTType.url.identifier, "public.url":
            return "URL"
        case UTType.fileURL.identifier, "public.file-url":
            return "File URL"
        case "com.apple.finder.drag.clipping":
            return "Finder Clipping"
        default:
            if let utType = UTType(uti) {
                return utType.localizedDescription ?? uti
            }
            return uti
        }
    }
}

/// Represents a single piece of data from the clipboard with its available formats
/// Implements efficient handling of potentially large data objects
struct ClipboardContent: Identifiable, Hashable {
    let id = UUID()
    let data: Data
    let formats: [ClipboardFormat]
    let description: String

    // Explicit initializer
    init(data: Data, formats: [ClipboardFormat], description: String) {
        self.data = data
        self.formats = formats
        self.description = description
    }

    var isPreviewable: Bool {
        return canRenderAsText || canRenderAsImage
    }

    var canRenderAsText: Bool {
        let textTypes = [
            UTType.plainText.identifier,
            UTType.rtf.identifier,
            UTType.html.identifier,
            "public.utf8-plain-text",
            "public.rtf",
            "public.html",
        ]
        return formats.contains { textTypes.contains($0.uti) }
    }

    var canRenderAsImage: Bool {
        let imageTypes = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.tiff.identifier,
            UTType.pdf.identifier,
            UTType.image.identifier,
            "public.png",
            "public.jpeg",
            "public.tiff",
            "com.adobe.pdf",
        ]
        return formats.contains { imageTypes.contains($0.uti) }
    }

    /// Returns approximate text size in characters without loading the entire content
    func getTextSize() -> Int? {
        // For plain text, estimate based on data size
        if formats.first(where: {
            $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
        }) != nil {
            // Probe the encoding and size without loading the entire string
            if let encoding = detectTextEncoding() {
                // Estimate size based on encoding
                let estimatedSize = data.count / encoding.characterWidth
                return estimatedSize
            }
        }

        // For RTF or HTML, we'd need to load it, which defeats the purpose of lazy loading
        // So we'll just return the data size as an approximation
        return data.count
    }

    /// Detects the most likely text encoding of the data
    /// Tests progressively through common encodings without loading the full content
    private func detectTextEncoding() -> String.Encoding? {
        // Try UTF-8 first (most common)
        if String(data: data.prefix(min(1024, data.count)), encoding: .utf8) != nil {
            return .utf8
        }
        // Then UTF-16
        if String(data: data.prefix(min(1024, data.count)), encoding: .utf16) != nil {
            return .utf16
        }
        // Then ASCII
        if String(data: data.prefix(min(1024, data.count)), encoding: .ascii) != nil {
            return .ascii
        }

        // Default to UTF-8 if we can't determine
        return .utf8
    }

    /// Gets a chunk of text at specified position with specified length
    /// Uses a memory-efficient approach for large text content:
    /// - For small texts (<100KB): loads entire content
    /// - For large texts: loads only the requested chunk
    /// - Parameters:
    ///   - offset: Character offset from the beginning
    ///   - length: Maximum length to read in characters
    /// - Returns: Tuple containing the requested chunk and the next offset to use for subsequent requests
    func getTextChunk(offset: Int, length: Int) -> (text: String, nextOffset: Int)? {
        // For plain text format
        if formats.first(where: {
            $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
        }) != nil {
            // For very small texts, just load the whole thing
            if data.count < 100_000 {
                if let fullText = String(data: data, encoding: .utf8) {
                    let endOffset = min(offset + length, fullText.count)
                    let startIndex =
                        fullText.index(
                            fullText.startIndex, offsetBy: offset, limitedBy: fullText.endIndex)
                        ?? fullText.endIndex
                    let endIndex =
                        fullText.index(
                            fullText.startIndex, offsetBy: endOffset, limitedBy: fullText.endIndex)
                        ?? fullText.endIndex
                    return (String(fullText[startIndex..<endIndex]), endOffset)
                }
                return nil
            }

            // For larger texts, we use byte-based chunking with boundary safety:
            // 1. Estimate character width based on encoding
            // 2. Add safety buffer to avoid cutting characters
            // 3. Convert only the needed chunk to string
            let encoding = detectTextEncoding() ?? .utf8
            let avgBytesPerChar = encoding.characterWidth
            let startByte = min(offset * avgBytesPerChar, data.count)
            let extraBytes = 16  // Buffer to ensure we don't cut characters
            let loadBytes = min(length * avgBytesPerChar + extraBytes, data.count - startByte)

            // Extract data chunk with extra bytes for safety
            let chunkData = data.subdata(in: startByte..<(startByte + loadBytes))

            // Convert to string
            if var chunkText = String(data: chunkData, encoding: encoding) {
                // Limit to requested length in characters
                if chunkText.count > length {
                    let endIndex =
                        chunkText.index(
                            chunkText.startIndex, offsetBy: length, limitedBy: chunkText.endIndex)
                        ?? chunkText.endIndex
                    chunkText = String(chunkText[..<endIndex])
                }

                // Return the text and the next offset
                return (chunkText, offset + chunkText.count)
            }
        }
        // Then try RTF format - cannot do partial loading, so load all for small files
        else if formats.first(where: {
            $0.uti == UTType.rtf.identifier || $0.uti == "public.rtf"
        }) != nil, data.count < 500_000 {
            if let attributedString = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
            {
                let string = attributedString.string
                // Apply offset and length if string is loaded successfully
                let endOffset = min(offset + length, string.count)
                if offset < string.count {
                    let startIndex = string.index(string.startIndex, offsetBy: offset)
                    let endIndex = string.index(string.startIndex, offsetBy: endOffset)
                    return (String(string[startIndex..<endIndex]), endOffset)
                }
            }
        }
        // Then try HTML format - cannot do partial loading, so load all for small files
        else if formats.first(where: {
            $0.uti == UTType.html.identifier || $0.uti == "public.html"
        }) != nil, data.count < 500_000 {
            if let attributedString = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil)
            {
                let string = attributedString.string
                // Apply offset and length
                let endOffset = min(offset + length, string.count)
                if offset < string.count {
                    let startIndex = string.index(string.startIndex, offsetBy: offset)
                    let endIndex = string.index(string.startIndex, offsetBy: endOffset)
                    return (String(string[startIndex..<endIndex]), endOffset)
                }
            }
        }
        // Try URL format
        else if formats.first(where: {
            $0.uti == UTType.url.identifier || $0.uti == "public.url"
        }) != nil {
            if let urlString = String(data: data, encoding: .utf8) {
                let endOffset = min(offset + length, urlString.count)
                if offset < urlString.count {
                    let startIndex = urlString.index(urlString.startIndex, offsetBy: offset)
                    let endIndex = urlString.index(urlString.startIndex, offsetBy: endOffset)
                    return (String(urlString[startIndex..<endIndex]), endOffset)
                }
            }
        }
        return nil
    }

    /// Gets the entire text representation if possible (backward compatibility)
    func getTextRepresentation() -> String? {
        // For small texts, just load directly
        if data.count < 100_000 {
            // Try to get text from plain text format first
            if formats.first(where: {
                $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
            }) != nil {
                return String(data: data, encoding: .utf8)
            }
            // Then try RTF format
            else if formats.first(where: {
                $0.uti == UTType.rtf.identifier || $0.uti == "public.rtf"
            }) != nil {
                if let attributedString = try? NSAttributedString(
                    data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil)
                {
                    return attributedString.string
                }
            }
            // Then try HTML format
            else if formats.first(where: {
                $0.uti == UTType.html.identifier || $0.uti == "public.html"
            }) != nil {
                if let attributedString = try? NSAttributedString(
                    data: data, options: [.documentType: NSAttributedString.DocumentType.html],
                    documentAttributes: nil)
                {
                    return attributedString.string
                }
            }
            // Try URL format
            else if formats.first(where: {
                $0.uti == UTType.url.identifier || $0.uti == "public.url"
            }) != nil {
                return String(data: data, encoding: .utf8)
            }
            return nil
        } else {
            // For large texts, get a preview with size information
            if let chunkResult = getTextChunk(offset: 0, length: 1000) {
                return chunkResult.text
                    + "\n\n[Large text: ~\(Utilities.formatSize(getTextSize() ?? data.count)) characters]"
            } else {
                return nil
            }
        }
    }

    // Custom implementation to compare contents semantically
    static func == (lhs: ClipboardContent, rhs: ClipboardContent) -> Bool {
        return lhs.data == rhs.data && lhs.formats == rhs.formats
            && lhs.description == rhs.description
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(data)
        hasher.combine(formats)
        hasher.combine(description)
    }
}

/// Represents a clipboard entry with its timestamp, change count, and available contents
/// Multiple contents can be present when the clipboard contains data in various formats
struct ClipboardHistoryItem: Identifiable, Equatable, Hashable {
    let id = UUID()
    let timestamp: Date
    let contents: [ClipboardContent]
    let sourceApplication: SourceApplicationInfo?

    var textRepresentation: String? {
        for content in contents {
            if let text = content.getTextRepresentation() {
                return text
            }
        }
        return nil
    }

    var hasImageRepresentation: Bool {
        return contents.contains { $0.canRenderAsImage }
    }

    // Custom implementation to compare contents semantically
    static func == (lhs: ClipboardHistoryItem, rhs: ClipboardHistoryItem) -> Bool {
        return lhs.contents == rhs.contents && lhs.sourceApplication == rhs.sourceApplication
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contents)
        hasher.combine(sourceApplication)
    }
}

/// Holds information about the application that was the source of a clipboard item
struct SourceApplicationInfo: Identifiable, Equatable, Hashable {
    let id = UUID()
    let bundleIdentifier: String?
    let applicationName: String?

    // Retrieve the icon using the bundle identifier when needed
    var applicationIcon: NSImage? {
        guard let bundleId = bundleIdentifier,
            let appBundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
            let bundle = Bundle(url: appBundle)
        else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: bundle.bundlePath)
    }

    init(bundleIdentifier: String?, applicationName: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
    }

    static func == (lhs: SourceApplicationInfo, rhs: SourceApplicationInfo) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.applicationName == rhs.applicationName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
        hasher.combine(applicationName)
    }
}

// MARK: - View Model

/// Responsible for monitoring clipboard changes and maintaining a history of items
/// Uses a timer-based polling approach to detect changes in the system clipboard
class ClipboardMonitor: ObservableObject {
    @Published var currentItem: ClipboardHistoryItem?
    @Published var history: [ClipboardHistoryItem] = []
    @Published var selectedHistoryItem: ClipboardHistoryItem?
    @Published var currentItemID: UUID?
    @Published var isLoadingHistory: Bool = false

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let logger = Logger(
        subsystem: "com.scottopell.spaperclip", category: "ClipboardMonitor")

    // Add persistence manager reference
    private let persistenceManager = ClipboardPersistenceManager.shared

    // Predefined UTIs we specifically handle in order of priority
    // Other types will still be processed but with default handling
    private let knownTypes = [
        "public.utf8-plain-text",
        "public.rtf",
        "public.html",
        "public.png",
        "public.jpeg",
        "public.tiff",
        "com.adobe.pdf",
        "public.url",
        "public.file-url",
        "com.apple.finder.drag.clipping",
    ]

    init() {
        logger.info("Application starting")

        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount

        // Start monitoring first to make UI responsive
        startMonitoring()
        updateFromClipboard()

        // Load history asynchronously to prevent UI hang
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loadSavedHistory()
        }

        logger.info("Initialization complete")
    }

    // Load previously saved clipboard history from Core Data
    private func loadSavedHistory() {
        logger.info("Loading clipboard history from Core Data")

        DispatchQueue.main.async { [weak self] in
            self?.isLoadingHistory = true
        }

        persistenceManager.loadHistoryItems { [weak self] loadedItems in
            guard let self = self else { return }

            DispatchQueue.main.async {
                // Notify SwiftUI before making changes to avoid intermediate updates
                self.objectWillChange.send()
                self.isLoadingHistory = false

                if !loadedItems.isEmpty {
                    self.history = loadedItems
                    self.selectedHistoryItem = self.history.first
                    self.logger.info("Loaded \(loadedItems.count) history items from persistence")
                } else {
                    self.logger.info("No history items found in persistence")
                }
            }
        }
    }

    func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
                [weak self] _ in
                self?.checkClipboard()
            }
        }
        logger.info("Clipboard monitoring started")
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        logger.info("Clipboard monitoring stopped")
    }

    func clearHistory() {
        history.removeAll()
        selectedHistoryItem = nil

        // Clear persisted history
        persistenceManager.clearAllHistory()
        logger.info("Clipboard history cleared and persistence data removed")
    }

    // MARK: - Selection Management

    /// Selects a history item
    func selectHistoryItem(_ item: ClipboardHistoryItem?) {
        // Ensure UI updates happen on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.selectHistoryItem(item)
            }
            return
        }

        self.selectedHistoryItem = item
    }

    /// Gets the application icon for a history item
    /// Prioritizes source app icon, falls back to generic clipboard icon
    func getIconForHistoryItem(_ item: ClipboardHistoryItem) -> NSImage? {
        if let sourceApp = item.sourceApplication, let icon = sourceApp.applicationIcon {
            return icon
        }

        return NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)
    }

    /// Gets the source application name for a history item
    func getSourceAppNameForHistoryItem(_ item: ClipboardHistoryItem) -> String {
        return item.sourceApplication?.applicationName ?? "Unknown Application"
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        if currentChangeCount != lastChangeCount {
            logger.info("Clipboard changed: \(self.lastChangeCount) -> \(currentChangeCount)")
            lastChangeCount = currentChangeCount
            DispatchQueue.main.async { [weak self] in
                self?.updateFromClipboard()
            }
        }
    }

    /// Captures clipboard content, groups it by unique data objects,
    /// and updates history with deduplicated entries
    private func updateFromClipboard() {
        let pasteboard = NSPasteboard.general

        guard let availableTypes = pasteboard.types else {
            return
        }

        // Content grouping strategy:
        // 1. Group identical binary data with different formats together
        // 2. Avoid duplicating large binary blobs in memory
        // 3. Create a consistent representation of each unique clipboard item
        class ContentGroup {
            let description: String
            var formats: [ClipboardFormat]

            init(description: String, format: ClipboardFormat) {
                self.description = description
                self.formats = [format]
            }
        }

        var contentGroups: [Data: ContentGroup] = [:]

        // First pass: collect all data and formats
        for type in knownTypes {
            if availableTypes.contains(NSPasteboard.PasteboardType(type)),
                let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type))
            {
                let description =
                    type == "public.utf8-plain-text"
                    ? (String(data: data, encoding: .utf8) ?? "Unknown text data")
                    : "Binary data (\(data.count) bytes)"

                let format = ClipboardFormat(uti: type)

                if let existing = contentGroups[data] {
                    existing.formats.append(format)
                } else {
                    contentGroups[data] = ContentGroup(description: description, format: format)
                }
            }
        }

        // Check for any other types
        for type in availableTypes {
            let typeString = type.rawValue
            if !knownTypes.contains(typeString),
                let data = pasteboard.data(forType: type)
            {
                let format = ClipboardFormat(uti: typeString)

                if let existing = contentGroups[data] {
                    existing.formats.append(format)
                } else {
                    contentGroups[data] = ContentGroup(
                        description: "Binary data (\(data.count) bytes)",
                        format: format
                    )
                }
            }
        }

        // Convert dictionary to array of ClipboardContent
        let contents = contentGroups.map { (data, group) in
            ClipboardContent(
                data: data,
                formats: group.formats,
                description: group.description
            )
        }

        // Get source application information
        var sourceAppInfo: SourceApplicationInfo? = nil

        // Get the frontmost application as our best guess for the source
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            sourceAppInfo = SourceApplicationInfo(
                bundleIdentifier: frontmostApp.bundleIdentifier,
                applicationName: frontmostApp.localizedName
            )
            self.logger.info(
                "Presumed source application: \(frontmostApp.localizedName ?? "Unknown")")
        }

        // Additional processing for specific pasteboard types that might contain origin info
        // Some applications put ownership information in custom pasteboard types
        for type in availableTypes {
            // Check for application-specific pasteboard types that might indicate source
            if type.rawValue.contains("CorePasteboardFlavorType")
                || type.rawValue.starts(with: "com.apple.") || type.rawValue.contains(".originator")
            {
                self.logger.info(
                    "Found potential source identifier pasteboard type: \(type.rawValue)")
                // These could be parsed to get more accurate source info
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Notify SwiftUI before making changes to avoid intermediate updates
            self.objectWillChange.send()

            let newItem = ClipboardHistoryItem(
                timestamp: Date(),
                contents: contents,
                sourceApplication: sourceAppInfo
            )

            // Update current item reference
            self.currentItem = newItem
            self.currentItemID = newItem.id

            if !contents.isEmpty {
                // Check if this item is a duplicate of any item already in history
                let isDuplicate = self.history.contains { $0 == newItem }

                if !isDuplicate {
                    // Insert at beginning (most recent first)
                    self.history.insert(newItem, at: 0)

                    // Directly update selectedHistoryItem without calling selectHistoryItem method
                    self.selectedHistoryItem = newItem

                    // Persist the new item to Core Data
                    self.persistenceManager.saveHistoryItem(newItem)

                } else {
                    // If it's a duplicate, find the matching item and move it to the top

                    if let index = self.history.firstIndex(where: { $0 == newItem }) {
                        let existingItem = self.history.remove(at: index)
                        self.history.insert(existingItem, at: 0)

                        // Directly update selectedHistoryItem without calling selectHistoryItem method
                        self.selectedHistoryItem = existingItem

                        self.logger.info("Duplicate item detected - moved existing to top")
                    }
                }

                // Limit history size to control memory usage
                // 100 items balances usability with performance
                if self.history.count > 100 {
                    self.history = Array(self.history.prefix(100))

                    // Also limit the persisted history size
                    self.persistenceManager.limitHistorySize(to: 100)
                }
            }

            // Update last change count after processing
            self.lastChangeCount = pasteboard.changeCount

            self.logger.info(
                "UI updated with clipboard content: \(contents.count) content groups")
        }
    }

    /// Copies only the plain text representation of a history item to the clipboard
    /// Bypasses the full clipboard data structure to ensure compatibility
    /// with applications that only support plain text
    func copyPlainTextOnly(_ item: ClipboardHistoryItem) {
        guard let textRepresentation = item.textRepresentation else {
            logger.warning("Cannot copy plain text: no text representation available")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textRepresentation, forType: .string)

        logger.info("Copied plain text only from history item")

        // Update the last change count to prevent the monitor from picking up this change
        lastChangeCount = pasteboard.changeCount
    }

    deinit {
        stopMonitoring()
    }
}

// Extension to get character width for different encodings
extension String.Encoding {
    /// Returns the typical number of bytes per character for this encoding
    /// Used for efficient text chunking without loading entire large strings
    var characterWidth: Int {
        switch self {
        case .ascii, .utf8, .isoLatin1, .isoLatin2:
            return 1
        case .utf16, .utf16BigEndian, .utf16LittleEndian:
            return 2
        case .utf32, .utf32BigEndian, .utf32LittleEndian:
            return 4
        default:
            return 1
        }
    }
}
