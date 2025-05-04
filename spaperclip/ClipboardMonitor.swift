//
//  ClipboardMonitor.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import SwiftUI
import os
import UniformTypeIdentifiers

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

    func getTextRepresentation() -> String? {
        // Try to get text from plain text format first
        if let textFormat = formats.first(where: {
            $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
        }) {
            return String(data: data, encoding: .utf8)
        }
        // Then try RTF format
        else if let rtfFormat = formats.first(where: {
            $0.uti == UTType.rtf.identifier || $0.uti == "public.rtf"
        }) {
            if let attributedString = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
            {
                return attributedString.string
            }
        }
        // Then try HTML format
        else if let htmlFormat = formats.first(where: {
            $0.uti == UTType.html.identifier || $0.uti == "public.html"
        }) {
            if let attributedString = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil)
            {
                return attributedString.string
            }
        }
        // Try URL format
        else if let urlFormat = formats.first(where: {
            $0.uti == UTType.url.identifier || $0.uti == "public.url"
        }) {
            return String(data: data, encoding: .utf8)
        }
        return nil
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
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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
    }

    /// Selects a content and updates format selection accordingly
    func selectContent(_ content: ClipboardContent?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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
    }

    /// Selects a format, ensuring it belongs to the selected content
    func selectFormat(_ format: ClipboardFormat?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let format = format,
                  let content = selectedContent,
                  content.formats.contains(where: { $0.id == format.id })
            else {
                return
            }
            
            selectedFormat = format
        }
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

    deinit {
        stopMonitoring()
    }
}
