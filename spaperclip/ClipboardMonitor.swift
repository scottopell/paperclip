//
//  ClipboardMonitor.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import SwiftUI
import UniformTypeIdentifiers
import os

// MARK: - Models

struct ClipboardFormat: Identifiable, Hashable {
    let id = UUID()
    let uti: String

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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(uti)
    }

    static func == (lhs: ClipboardFormat, rhs: ClipboardFormat) -> Bool {
        return lhs.id == rhs.id && lhs.uti == rhs.uti
    }
}

struct ClipboardContent: Identifiable, Hashable {
    let id = UUID()
    let data: Data
    var formats: [ClipboardFormat]
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
    /// - Parameters:
    ///   - offset: Character offset from the beginning
    ///   - length: Maximum length to read in characters
    /// - Returns: String containing the requested chunk, or nil if not possible
    func getTextChunk(offset: Int, length: Int) -> String? {
        // For plain text format
        if formats.first(where: {
            $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
        }) != nil {
            // For very small texts, just load the whole thing
            if data.count < 100_000 {
                return String(data: data, encoding: .utf8)
            }

            // For larger texts, try to load just the chunk
            // This is an approximation as bytes != characters for many encodings
            let encoding = detectTextEncoding() ?? .utf8
            let bytesPerChar = encoding.characterWidth

            // Calculate byte range (approximate)
            let startByte = min(offset * bytesPerChar, data.count)
            let maxBytes = min(length * bytesPerChar, data.count - startByte)

            // Extract data chunk
            let chunkData = data.subdata(in: startByte..<(startByte + maxBytes))

            // Convert to string
            return String(data: chunkData, encoding: encoding)
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
                let endIndex = min(offset + length, string.count)
                if offset < string.count {
                    let startIndex = string.index(string.startIndex, offsetBy: offset)
                    let endIndex = string.index(string.startIndex, offsetBy: endIndex)
                    return String(string[startIndex..<endIndex])
                }
                return nil
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
                let endIndex = min(offset + length, string.count)
                if offset < string.count {
                    let startIndex = string.index(string.startIndex, offsetBy: offset)
                    let endIndex = string.index(string.startIndex, offsetBy: endIndex)
                    return String(string[startIndex..<endIndex])
                }
                return nil
            }
        }
        // Try URL format
        else if formats.first(where: {
            $0.uti == UTType.url.identifier || $0.uti == "public.url"
        }) != nil {
            return String(data: data, encoding: .utf8)
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
            if let previewText = getTextChunk(offset: 0, length: 1000) {
                return previewText
                    + "\n\n[Large text: ~\(formatTextSize(getTextSize() ?? data.count)) characters]"
            } else {
                return nil
            }
        }
    }

    /// Format text size with appropriate units
    private func formatTextSize(_ size: Int) -> String {
        if size < 1_000 {
            return "\(size)"
        } else if size < 1_000_000 {
            return String(format: "%.1fK", Double(size) / 1_000)
        } else {
            return String(format: "%.1fM", Double(size) / 1_000_000)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(data)
    }

    static func == (lhs: ClipboardContent, rhs: ClipboardContent) -> Bool {
        return lhs.id == rhs.id
    }
}

struct ClipboardHistoryItem: Identifiable, Equatable, Hashable {
    let id = UUID()
    let timestamp: Date
    let changeCount: Int
    var contents: [ClipboardContent]

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

    static func == (lhs: ClipboardHistoryItem, rhs: ClipboardHistoryItem) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - View Model

class ClipboardMonitor: ObservableObject {
    @Published var currentItem: ClipboardHistoryItem?
    @Published var history: [ClipboardHistoryItem] = []
    @Published var selectedContent: ClipboardContent?
    @Published var selectedFormat: ClipboardFormat?
    @Published var selectedHistoryItem: ClipboardHistoryItem?
    @Published var currentItemID: UUID?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let logger = Logger(
        subsystem: "com.scottopell.spaperclip", category: "ClipboardMonitor")

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

        startMonitoring()
        updateFromClipboard()

        logger.info("Initialization complete")
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
        selectedContent = nil
        selectedFormat = nil
    }

    // MARK: - Selection Management

    /// Selects a history item and updates content/format selections accordingly
    func selectHistoryItem(_ item: ClipboardHistoryItem?) {
        // Ensure UI updates happen on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.selectHistoryItem(item)
            }
            return
        }

        self.selectedHistoryItem = item
        guard let item = item, !item.contents.isEmpty else {
            selectedContent = nil
            selectedFormat = nil
            return
        }

        // If current content is in the new history item, keep it selected
        if let currentContent = selectedContent,
            item.contents.contains(where: { $0.id == currentContent.id })
        {
            // Content is still valid, keep it selected
        } else {
            // Default to text content if available, otherwise first content
            if let textContent = item.contents.first(where: { $0.canRenderAsText }) {
                selectContent(textContent)
            } else {
                selectContent(item.contents.first)
            }
        }
    }

    /// Selects a content and updates format selection accordingly
    func selectContent(_ content: ClipboardContent?) {
        // Ensure UI updates happen on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.selectContent(content)
            }
            return
        }

        selectedContent = content

        guard let content = content else {
            selectedFormat = nil
            return
        }

        // If current format is in the new content, keep it selected
        if let currentFormat = selectedFormat,
            content.formats.contains(where: { $0.id == currentFormat.id })
        {
            // Format is still valid, keep it selected
        } else {
            // Default to text format if available, otherwise first format
            if content.canRenderAsText {
                if let textFormat = content.formats.first(where: {
                    $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
                }) {
                    selectedFormat = textFormat
                } else {
                    selectedFormat = content.formats.first
                }
            } else {
                selectedFormat = content.formats.first
            }
        }
    }

    /// Selects a format, ensuring it belongs to the selected content
    func selectFormat(_ format: ClipboardFormat?) {
        // Ensure UI updates happen on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.selectFormat(format)
            }
            return
        }

        guard let format = format,
            let content = selectedContent,
            content.formats.contains(where: { $0.id == format.id })
        else {
            return
        }

        selectedFormat = format
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

    private func updateFromClipboard() {
        let pasteboard = NSPasteboard.general

        guard let availableTypes = pasteboard.types else {
            return
        }

        // Create a dictionary to group data by content
        var contentGroups: [Data: (description: String, formats: [ClipboardFormat])] = [:]

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

                if contentGroups[data] != nil {
                    contentGroups[data]?.formats.append(format)
                } else {
                    contentGroups[data] = (description: description, formats: [format])
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

                if contentGroups[data] != nil {
                    contentGroups[data]?.formats.append(format)
                } else {
                    contentGroups[data] = (
                        description: "Binary data (\(data.count) bytes)", formats: [format]
                    )
                }
            }
        }

        // Convert dictionary to array of ClipboardContent
        let contents = contentGroups.map { (data, info) in
            ClipboardContent(
                data: data,
                formats: info.formats,
                description: info.description
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let newItem = ClipboardHistoryItem(
                timestamp: Date(),
                changeCount: pasteboard.changeCount,
                contents: contents
            )

            // Update current item reference
            self.currentItem = newItem
            self.currentItemID = newItem.id

            if !contents.isEmpty {
                // Insert at beginning (most recent first)
                self.history.insert(newItem, at: 0)

                // Limit history size
                if self.history.count > 100 {
                    self.history = Array(self.history.prefix(100))
                }

                // Select the new clipboard item as the active selection
                self.selectHistoryItem(newItem)
            }

            self.logger.info(
                "UI updated with new clipboard content: \(contents.count) content groups")
        }
    }

    /// Gets a valid content for the given history item, prioritizing text content
    func getDefaultContentForItem(_ item: ClipboardHistoryItem) -> ClipboardContent? {
        if let textContent = item.contents.first(where: { $0.canRenderAsText }) {
            return textContent
        }
        return item.contents.first
    }

    /// Gets a valid format for the given content, prioritizing plain text formats
    func getDefaultFormatForContent(_ content: ClipboardContent) -> ClipboardFormat? {
        if content.canRenderAsText {
            if let textFormat = content.formats.first(where: {
                $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
            }) {
                return textFormat
            }
        }
        return content.formats.first
    }

    /// Copies only the plain text representation of a history item to the clipboard
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
