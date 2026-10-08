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
import libxml2
import os

// MARK: - Models

/// Represents a clipboard data format with its associated UTI (Uniform Type Identifier)
struct ClipboardFormat: Identifiable, Hashable {
    // SwiftUI identity is per value instance; semantic equality is the UTI.
    let id = UUID()
    let uti: String

    static func == (lhs: ClipboardFormat, rhs: ClipboardFormat) -> Bool {
        lhs.uti == rhs.uti
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uti)
    }

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

    /// A compact label for representation selectors.
    var shortTypeName: String {
        let normalizedUTI = uti.lowercased()
        if normalizedUTI.contains("png") { return "PNG" }
        if normalizedUTI.contains("tiff") { return "TIFF" }
        if normalizedUTI.contains("jpeg") || normalizedUTI.contains("jpg") { return "JPEG" }
        if normalizedUTI.contains("pdf") { return "PDF" }
        if normalizedUTI.contains("html") { return "HTML" }
        if normalizedUTI.contains("rtf") { return "Rich Text" }
        if normalizedUTI.contains("text") || normalizedUTI.contains("string") { return "Plain Text" }
        if normalizedUTI.contains("file-url") { return "File URL" }
        if normalizedUTI.contains("url") { return "URL" }
        return typeName
    }
}

/// Lazily retains decoded searchable text while bounding aggregate memory use.
/// Eviction only affects performance; search results remain deterministic.
final class ClipboardSearchTextCache {
    // The history cap is 100 items. This admits the measured 100 × 1 MiB workload
    // while remaining explicitly bounded and evictable under larger real-world values.
    static let shared = ClipboardSearchTextCache(totalCostLimit: 128 * 1_024 * 1_024)

    private let cache = NSCache<NSUUID, NSString>()
    private let failedRichText = NSCache<NSUUID, NSNumber>()
    private let matchCache = NSCache<NSString, NSNumber>()
    private let lock = NSLock()
    private final class PendingDecode {
        let done = DispatchGroup()
        var result: String?

        init() { done.enter() }
    }
    private var inFlight: [UUID: PendingDecode] = [:]
    private var generation = 0
    private var decodeCounts: [UUID: Int] = [:]

    init(totalCostLimit: Int) {
        cache.totalCostLimit = totalCostLimit
        failedRichText.countLimit = 1_000
        matchCache.countLimit = 10_000
    }

    func text(for content: ClipboardContent, decode: () -> String?) -> String? {
        let key = content.id as NSUUID
        lock.lock()
        if let cached = cache.object(forKey: key) {
            lock.unlock()
            return cached as String
        }
        if failedRichText.object(forKey: key) != nil {
            lock.unlock()
            return nil
        }
        if let pending = inFlight[content.id] {
            lock.unlock()
            pending.done.wait() // Never hold the cache lock during another item's decode.
            return pending.result
        }
        let pending = PendingDecode()
        inFlight[content.id] = pending
        let currentGeneration = generation
        lock.unlock()

        let result = decode()

        lock.lock()
        if generation == currentGeneration {
            if let result {
                cache.setObject(result as NSString, forKey: key, cost: result.utf8.count)
                decodeCounts[content.id, default: 0] += 1
            } else if content.decodesRichSearchText {
                failedRichText.setObject(NSNumber(value: true), forKey: key)
            }
            inFlight.removeValue(forKey: content.id)
        }
        pending.result = result
        lock.unlock()
        pending.done.leave()
        return result
    }

    func matches(_ query: String, in content: ClipboardContent) -> Bool {
        let key = "\(content.id.uuidString)\u{1F}\(query)" as NSString
        if let cached = matchCache.object(forKey: key) { return cached.boolValue }

        let result = text(for: content) {
            content.decodeSearchableText()
        }?.localizedCaseInsensitiveContains(query) == true
        matchCache.setObject(NSNumber(value: result), forKey: key)
        return result
    }

    func decodeCount(for content: ClipboardContent) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return decodeCounts[content.id, default: 0]
    }

    func removeAll() {
        lock.lock()
        generation &+= 1
        cache.removeAllObjects()
        failedRichText.removeAllObjects()
        matchCache.removeAllObjects()
        inFlight.removeAll()
        decodeCounts.removeAll()
        lock.unlock()
    }
}


/// Extracts local HTML text without a browser, resource loads, or XPC.
/// WebKit's async HTML importer loads external image URLs, even with a CSP meta tag.
/// This approximates rendered text; it does not interpret CSS layout or visibility.
enum LocalHTMLText {
    // DOM construction can use far more memory than the source HTML bytes.
    // Raw representations remain restorable regardless of this preview limit.
    static let maximumImportBytes = 2_000_000

    static func decode(_ data: Data) -> String? {
        guard !data.isEmpty, data.count <= maximumImportBytes else { return nil }
        let options = Int32(HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue
            | HTML_PARSE_NOWARNING.rawValue)
        let document = data.withUnsafeBytes { bytes in
            htmlReadMemory(bytes.baseAddress!.assumingMemoryBound(to: CChar.self),
                           Int32(bytes.count), nil, nil, options)
        }
        guard let document else { return nil }
        defer { xmlFreeDoc(document) }
        guard let reader = xmlReaderWalker(document) else { return nil }
        defer { xmlFreeTextReader(reader) }

        func value(_ pointer: UnsafePointer<xmlChar>?) -> String {
            guard let pointer else { return "" }
            return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
        }
        let skipped: Set<String> = ["head", "script", "style", "template", "noscript", "svg"]
        let blocks: Set<String> = ["article", "blockquote", "br", "dd", "div", "dt",
                                   "h1", "h2", "h3", "h4", "h5", "h6", "hr", "li",
                                   "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul"]
        var text = ""
        var pendingSpace = false
        var skippedDepth: Int32?
        var preformattedDepth: Int32?
        func newline() {
            pendingSpace = false
            if !text.isEmpty && !text.hasSuffix("\n") { text.append("\n") }
        }
        while true {
            let status = xmlTextReaderRead(reader)
            if status == 0 { break }
            if status < 0 { return nil }
            let kind = xmlTextReaderNodeType(reader)
            let depth = xmlTextReaderDepth(reader)
            if let hiddenDepth = skippedDepth {
                if kind == XML_READER_TYPE_END_ELEMENT.rawValue && depth == hiddenDepth {
                    skippedDepth = nil
                }
                continue
            }
            if kind == XML_READER_TYPE_ELEMENT.rawValue {
                let tag = value(xmlTextReaderConstLocalName(reader)).lowercased()
                if skipped.contains(tag) {
                    if xmlTextReaderIsEmptyElement(reader) != 1 { skippedDepth = depth }
                } else {
                    if blocks.contains(tag) { newline() }
                    if tag == "pre" { preformattedDepth = depth }
                }
            } else if kind == XML_READER_TYPE_END_ELEMENT.rawValue {
                let tag = value(xmlTextReaderConstLocalName(reader)).lowercased()
                if tag == "pre" && preformattedDepth == depth { preformattedDepth = nil }
                if blocks.contains(tag) { newline() }
            } else if kind == XML_READER_TYPE_TEXT.rawValue
                || kind == XML_READER_TYPE_CDATA.rawValue
                || kind == XML_READER_TYPE_SIGNIFICANT_WHITESPACE.rawValue {
                let fragment = value(xmlTextReaderConstValue(reader))
                if preformattedDepth != nil {
                    text += fragment
                } else {
                    for character in fragment {
                        if character.isWhitespace {
                            pendingSpace = true
                        } else {
                            if pendingSpace && !text.isEmpty && !text.hasSuffix("\n") {
                                text.append(" ")
                            }
                            pendingSpace = false
                            text.append(character)
                        }
                    }
                }
            }
        }
        return text.trimmingCharacters(in: .newlines)
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
    /// Decodes plain text once, caches it, then returns character-safe slices.
    /// - Parameters:
    ///   - offset: Character offset from the beginning
    ///   - length: Maximum length to read in characters
    /// - Returns: Tuple containing the requested chunk and the next offset to use for subsequent requests
    func getTextChunk(offset: Int, length: Int) -> (text: String, nextOffset: Int)? {
        // For plain text format
        if formats.first(where: {
            $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
        }) != nil {
            guard let fullText = decodedPlainText() else { return nil }

            let totalCount = fullText.count
            guard offset < totalCount else { return nil }

            let startIndex =
                fullText.index(fullText.startIndex, offsetBy: offset, limitedBy: fullText.endIndex)
                ?? fullText.endIndex
            let endOffset = min(offset + length, totalCount)
            let endIndex =
                fullText.index(fullText.startIndex, offsetBy: endOffset, limitedBy: fullText.endIndex)
                ?? fullText.endIndex

            let chunkText = String(fullText[startIndex..<endIndex])
            return (chunkText, endOffset)
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
        // HTML text is parsed locally; UI preview callers use the background indexer.
        else if usesLocalHTMLText, data.count < 500_000,
                let string = LocalHTMLText.decode(data), offset < string.count {
            let start = string.index(string.startIndex, offsetBy: offset)
            let endOffset = min(offset + length, string.count)
            let end = string.index(string.startIndex, offsetBy: endOffset)
            return (String(string[start..<end]), endOffset)
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

    private func decodedPlainText(cache: ClipboardSearchTextCache = .shared) -> String? {
        cache.text(for: self) { decodeSearchableText() }
    }

    /// Decodes the complete text used by the detail view. This runs off the main
    /// thread in `LazyTextView`, then AppKit receives a single string assignment.
    func textForDisplay() -> String? {
        if formats.contains(where: {
            $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
        }) {
            return decodedPlainText()
        }

        if formats.contains(where: {
            $0.uti == UTType.rtf.identifier || $0.uti == "public.rtf"
        }) {
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ).string
        }

        if formats.contains(where: {
            $0.uti == UTType.url.identifier || $0.uti == "public.url"
        }) {
            return String(data: data, encoding: .utf8)
        }
        if usesLocalHTMLText { return LocalHTMLText.decode(data) }

        return nil
    }

    /// Returns complete text for filtering. Plain text and URLs are decoded in full.
    /// Rich content retains a 500 KB safety bound. HTML parsing is local and
    /// cannot request linked resources; UI callers run it off the main thread.
    func searchableText(cache: ClipboardSearchTextCache = .shared) -> String? {
        cache.text(for: self) { decodeSearchableText() }
    }

    /// HTML uses the local parser; RTF takes precedence when a group advertises both.
    var usesLocalHTMLText: Bool {
        let identifiers = Set(formats.map(\.uti))
        return decodesRichSearchText
            && !identifiers.contains(UTType.rtf.identifier) && !identifiers.contains("public.rtf")
            && (identifiers.contains(UTType.html.identifier) || identifiers.contains("public.html"))
    }

    var decodesRichSearchText: Bool {
        let identifiers = Set(formats.map(\.uti))
        if identifiers.contains(UTType.plainText.identifier)
            || identifiers.contains("public.utf8-plain-text")
            || identifiers.contains(UTType.url.identifier)
            || identifiers.contains("public.url")
            || identifiers.contains(UTType.fileURL.identifier)
            || identifiers.contains("public.file-url") { return false }
        return identifiers.contains(UTType.rtf.identifier) || identifiers.contains("public.rtf")
            || identifiers.contains(UTType.html.identifier) || identifiers.contains("public.html")
    }

    fileprivate func decodeSearchableText() -> String? {
        let identifiers = Set(formats.map(\.uti))
        let isPlainText = identifiers.contains(UTType.plainText.identifier)
            || identifiers.contains("public.utf8-plain-text")
        if isPlainText {
            // A UTF-16 byte stream containing only ASCII code points can also be
            // technically valid UTF-8 full of NULs. Honor its BOM before probing UTF-8.
            let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
            if hasUTF16BOM, let text = String(data: data, encoding: .utf16) { return text }
            if let text = String(data: data, encoding: .utf8) { return text }
            if let text = String(data: data, encoding: .utf16) { return text }
            return String(data: data, encoding: .ascii)
        }

        let isURL = identifiers.contains(UTType.url.identifier)
            || identifiers.contains("public.url")
            || identifiers.contains(UTType.fileURL.identifier)
            || identifiers.contains("public.file-url")
        if isURL { return String(data: data, encoding: .utf8) }

        guard data.count < 500_000 else { return nil }
        if identifiers.contains(UTType.rtf.identifier) || identifiers.contains("public.rtf") {
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ).string
        }
        if usesLocalHTMLText { return LocalHTMLText.decode(data) }
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
            else if usesLocalHTMLText {
                return LocalHTMLText.decode(data)
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
    let id: UUID
    let timestamp: Date
    let contents: [ClipboardContent]
    let sourceApplication: SourceApplicationInfo?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        contents: [ClipboardContent],
        sourceApplication: SourceApplicationInfo?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.contents = contents
        self.sourceApplication = sourceApplication
    }

    /// True when this item can reproduce every representation in a pasteboard capture.
    /// This treats a plain-text restore from a rich item as the same history entry.
    func containsRepresentations(from capturedContents: [ClipboardContent]) -> Bool {
        let available = contents.reduce(into: [String: Data]()) { result, content in
            for format in content.formats { result[format.uti] = content.data }
        }
        return capturedContents.allSatisfy { content in
            content.formats.allSatisfy { format in available[format.uti] == content.data }
        }
    }

    var textRepresentation: String? {
        for content in contents {
            if let text = content.getTextRepresentation() {
                return text
            }
        }
        return nil
    }

    func matchesSearchText(
        _ query: String,
        cache: ClipboardSearchTextCache = .shared
    ) -> Bool {
        contents.contains { content in
            cache.matches(query, in: content)
        }
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

enum ClipboardHistoryState {
    static func promoting(
        _ item: ClipboardHistoryItem,
        in history: [ClipboardHistoryItem],
        at timestamp: Date
    ) -> (item: ClipboardHistoryItem, history: [ClipboardHistoryItem]) {
        let promoted = ClipboardHistoryItem(
            id: item.id,
            timestamp: timestamp,
            contents: item.contents,
            sourceApplication: item.sourceApplication
        )
        var reordered = history.filter { $0.id != item.id }
        reordered.insert(promoted, at: 0)
        return (promoted, reordered)
    }
}

/// Resolves source-application icons once per bundle identifier.
/// `NSCache` bounds memory automatically and is safe to access from multiple threads.
final class SourceApplicationIconCache {
    static let shared = SourceApplicationIconCache()

    typealias Loader = (String) -> NSImage?

    private let cache = NSCache<NSString, NSImage>()
    private let loader: Loader

    init(countLimit: Int = 64, loader: @escaping Loader = SourceApplicationIconCache.loadIcon) {
        cache.countLimit = countLimit
        self.loader = loader
    }

    func icon(for bundleIdentifier: String) -> NSImage? {
        let key = bundleIdentifier as NSString
        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        guard let icon = loader(bundleIdentifier) else { return nil }
        cache.setObject(icon, forKey: key)
        return icon
    }

    private static func loadIcon(for bundleIdentifier: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier)
        else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

/// Holds information about the application that was the source of a clipboard item
struct SourceApplicationInfo: Identifiable, Equatable, Hashable {
    let id = UUID()
    let bundleIdentifier: String?
    let applicationName: String?

    // Retrieve the icon using the bundle identifier when needed.
    var applicationIcon: NSImage? {
        guard let bundleIdentifier else { return nil }
        return SourceApplicationIconCache.shared.icon(for: bundleIdentifier)
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
    @Published private(set) var isCapturingHistory = false
    @Published private(set) var captureIncomplete = false

    private var timer: Timer?
    private let pasteboard: NSPasteboard
    private let captureQueue = DispatchQueue(label: "com.scottopell.spaperclip.capture", qos: .userInitiated)
    // Main-queue state. Only one worker read may be pending per monitor.
    private var captureInFlight = false
    private var captureGeneration = 0
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

    // Add a flag to track initial state
    private var initialStartupComplete = false

    init(loadPersistedHistory: Bool = true, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        logger.info("Application starting")

        lastChangeCount = pasteboard.changeCount

        guard loadPersistedHistory else {
            initialStartupComplete = true
            logger.info("Initialization completed without persistence or monitoring")
            return
        }

        // Simply load history first
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loadSavedHistory { [weak self] in
                // After history is loaded, mark startup as complete and start monitoring
                DispatchQueue.main.async {
                    self?.initialStartupComplete = true
                    self?.reconcileCurrentPasteboard(force: true)
                    self?.startMonitoring()
                    self?.logger.info("Initial startup complete, monitoring started")
                }
            }
        }

        logger.info("Initialization sequence started")
    }

    // Load previously saved clipboard history from Core Data
    private func loadSavedHistory(completion: @escaping () -> Void) {
        logger.info("Loading clipboard history from Core Data")

        DispatchQueue.main.async { [weak self] in
            self?.isLoadingHistory = true
        }

        persistenceManager.loadHistoryItems { [weak self] loadedItems in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoadingHistory = false

                if !loadedItems.isEmpty {
                    self.history = loadedItems

                    // Persistence cannot prove what is currently on the system pasteboard.
                    // Select the newest entry for browsing, but leave the Current marker unset.
                    self.selectedHistoryItem = self.history.first
                    self.currentItem = nil
                    self.currentItemID = nil

                    self.logger.info("Loaded \(loadedItems.count) history items from persistence")
                } else {
                    self.logger.info("No history items found in persistence")
                }

                // Call completion handler
                completion()
            }
        }
    }

    func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
                [weak self] _ in
                self?.checkClipboard()
            }
            self.logger.info("Clipboard monitoring started")
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        captureGeneration &+= 1
        logger.info("Clipboard monitoring stopped")
    }

    func clearHistory(completion: (() -> Void)? = nil) {
        captureGeneration &+= 1
        lastChangeCount = pasteboard.changeCount
        captureIncomplete = false
        ClipboardSearchTextCache.shared.removeAll()
        RichSearchIndexer.shared.removeAll()
        guard !history.isEmpty else {
            completion?()
            return
        }

        history.removeAll()
        currentItem = nil
        currentItemID = nil
        selectedHistoryItem = nil

        persistenceManager.clearAllHistory { [weak self] in
            self?.logger.info("Clipboard history cleared and persistence data removed")
            completion?()
        }
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
        reconcileCurrentPasteboard()
    }

    /// Schedules a read without making the polling timer or Quick Search wait for a data provider.
    func reconcileCurrentPasteboard(force: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard initialStartupComplete else { return }
        let pasteboard = self.pasteboard
        let changed = pasteboard.changeCount != lastChangeCount
        if changed {
            // The old Current marker no longer describes the pasteboard. Keep browsing selection.
            currentItem = nil
            currentItemID = nil
        }
        guard !captureInFlight, force || changed else { return }
        let knownTypes = self.knownTypes
        let generation = captureGeneration
        let lastCount = lastChangeCount
        let sourceApp = NSWorkspace.shared.frontmostApplication.map {
            SourceApplicationInfo(bundleIdentifier: $0.bundleIdentifier, applicationName: $0.localizedName)
        }
        captureInFlight = true
        isCapturingHistory = true
        captureQueue.async { [weak self] in
            let startCount = pasteboard.changeCount
            let captured: ClipboardHistoryItem? = (force || startCount != lastCount)
                ? Self.updateFromClipboard(pasteboard: pasteboard, knownTypes: knownTypes,
                                           sourceAppInfo: sourceApp)
                : nil
            let hasAdvertisedTypes = !(pasteboard.types ?? []).isEmpty
            let endCount = pasteboard.changeCount
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.captureInFlight = false
                self.isCapturingHistory = false
                guard self.captureGeneration == generation else { return }
                // Do not publish a mixed snapshot, a superseded capture, or our own write.
                guard startCount == endCount, self.pasteboard.changeCount == endCount else {
                    self.currentItem = nil
                    self.currentItemID = nil
                    self.reconcileCurrentPasteboard()
                    return
                }
                guard force || endCount != self.lastChangeCount else { return }
                guard let captured else {
                    // Whether empty or incomplete, no saved item is current. Consume this
                    // change count so a failed provider is not read again on every poll.
                    self.currentItem = nil
                    self.currentItemID = nil
                    self.lastChangeCount = endCount
                    self.captureIncomplete = hasAdvertisedTypes
                    return
                }
                self.captureIncomplete = false
                self.lastChangeCount = endCount
                self.applyHistoryItem(captured)
            }
        }
    }

    /// Reads every representation on the worker; a provider may block this thread.
    /// A changeCount check before and after this function guards the entire snapshot.
    private static func updateFromClipboard(
        pasteboard: NSPasteboard, knownTypes: [String], sourceAppInfo: SourceApplicationInfo?
    ) -> ClipboardHistoryItem? {
        guard let availableTypes = pasteboard.types else { return nil }

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
            if availableTypes.contains(NSPasteboard.PasteboardType(type)) {
                guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type))
                else { return nil }
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
            if !knownTypes.contains(typeString) {
                guard let data = pasteboard.data(forType: type) else { return nil }
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

        guard !contents.isEmpty else { return nil }
        return ClipboardHistoryItem(
            timestamp: Date(), contents: contents, sourceApplication: sourceAppInfo
        )
    }

    private func markCurrent(_ item: ClipboardHistoryItem) {
        currentItem = item
        currentItemID = item.id
        selectedHistoryItem = item
    }

    /// Copies exactly one format without recording the app's own write.
    @discardableResult
    func copyFormat(
        _ format: ClipboardFormat,
        from content: ClipboardContent,
        in item: ClipboardHistoryItem
    ) -> Bool {
        guard canReplacePasteboard() else { return false }
        let pasteboard = self.pasteboard
        guard Utilities.copy(format, from: content, to: pasteboard,
                             expectedChangeCount: lastChangeCount) else {
            reconcileCurrentPasteboard()
            logger.warning("Cannot copy format: no representation was written")
            return false
        }

        captureGeneration &+= 1
        captureIncomplete = false
        lastChangeCount = pasteboard.changeCount
        promoteToCurrent(item)
        logger.info("Copied one format from history item")
        return true
    }

    /// Applies a capture to history. Pasteboard capture and tests share this path.
    func applyHistoryItem(_ newItem: ClipboardHistoryItem, persist: Bool = true) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !newItem.contents.isEmpty else { return }

        if let existingItem = history.first(where: {
            $0.containsRepresentations(from: newItem.contents)
        }) {
            let promoted = ClipboardHistoryState.promoting(
                existingItem, in: history, at: newItem.timestamp)
            history = promoted.history
            markCurrent(promoted.item)
            if persist {
                persistenceManager.promoteHistoryItem(existingItem, to: promoted.item.timestamp)
            }
            logger.info("Duplicate item detected - moved existing to top")
        } else {
            history.insert(newItem, at: 0)
            markCurrent(newItem)
            if persist { persistenceManager.saveHistoryItem(newItem) }
        }

        if history.count > 100 {
            history = Array(history.prefix(100))
            if persist { persistenceManager.limitHistorySize(to: 100) }
        }
    }

    /// Copies one content group without recording the app's own write.
    @discardableResult
    func copyContent(_ content: ClipboardContent, in item: ClipboardHistoryItem) -> Bool {
        guard canReplacePasteboard() else { return false }
        let pasteboard = self.pasteboard
        guard Utilities.copyToClipboard(content, to: pasteboard,
                                        expectedChangeCount: lastChangeCount) else {
            reconcileCurrentPasteboard()
            logger.warning("Cannot copy content: no representation was written")
            return false
        }

        captureGeneration &+= 1
        captureIncomplete = false
        lastChangeCount = pasteboard.changeCount
        promoteToCurrent(item)
        logger.info("Copied content from history item")
        return true
    }

    /// Copies all representations of a history item without recording the app's own write.
    @discardableResult
    func copyAllContentTypes(_ item: ClipboardHistoryItem) -> Bool {
        guard canReplacePasteboard() else { return false }
        let pasteboard = self.pasteboard
        guard Utilities.copyAllContentTypes(from: item, to: pasteboard,
                                            expectedChangeCount: lastChangeCount) else {
            reconcileCurrentPasteboard()
            logger.warning("Cannot copy history item: no content was written")
            return false
        }

        captureGeneration &+= 1
        captureIncomplete = false
        lastChangeCount = pasteboard.changeCount
        promoteToCurrent(item)
        logger.info("Copied all content types from history item")
        return true
    }

    /// Copies only the plain text representation of a history item to the clipboard
    /// Bypasses the full clipboard data structure to ensure compatibility
    /// with applications that only support plain text
    @discardableResult
    func copyPlainTextOnly(_ item: ClipboardHistoryItem) -> Bool {
        guard canReplacePasteboard() else { return false }
        let pasteboard = self.pasteboard
        guard Utilities.copyPlainText(from: item, to: pasteboard,
                                      expectedChangeCount: lastChangeCount) else {
            reconcileCurrentPasteboard()
            logger.warning("Cannot copy plain text: pasteboard write failed")
            return false
        }

        captureGeneration &+= 1
        captureIncomplete = false
        lastChangeCount = pasteboard.changeCount
        promoteToCurrent(item)
        logger.info("Copied plain text only from history item")
        return true
    }

    /// Do not replace an external write that has not yet been captured.
    private func canReplacePasteboard() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !captureInFlight, !captureIncomplete, pasteboard.changeCount == lastChangeCount else {
            reconcileCurrentPasteboard()
            logger.warning("Cannot copy: clipboard capture is pending or incomplete")
            return false
        }
        return true
    }

    /// Called after an explicitly transformed plain-text representation is written.
    func promoteRestoredItem(_ item: ClipboardHistoryItem) {
        guard !captureInFlight, !captureIncomplete else { return }
        lastChangeCount = pasteboard.changeCount
        captureGeneration &+= 1
        captureIncomplete = false
        promoteToCurrent(item)
    }

    private func promoteToCurrent(_ item: ClipboardHistoryItem) {
        let promoted = ClipboardHistoryState.promoting(item, in: history, at: Date())
        history = promoted.history
        currentItem = promoted.item
        currentItemID = promoted.item.id
        selectedHistoryItem = promoted.item
        persistenceManager.promoteHistoryItem(item, to: promoted.item.timestamp)
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
