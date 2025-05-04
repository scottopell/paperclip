import AppKit
import Combine
import PDFKit
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

    var textRepresentation: String {
        for content in contents {
            if let text = content.getTextRepresentation() {
                return text
            }
        }
        return "No text representation available"
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
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
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        if currentChangeCount != lastChangeCount {
            logger.info("Clipboard changed: \(self.lastChangeCount) -> \(currentChangeCount)")
            lastChangeCount = currentChangeCount
            updateFromClipboard()
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
            // Set the current item ID
            self.currentItemID = newItem.id

            if !contents.isEmpty {
                // Insert at beginning (most recent first)
                self.history.insert(newItem, at: 0)

                // Limit history size
                if self.history.count > 100 {
                    self.history = Array(self.history.prefix(100))
                }

                // Set initially selected content to text content if available
                if let textContent = contents.first(where: { $0.canRenderAsText }) {
                    self.selectedContent = textContent
                    // Set initially selected format to a text format if available
                    if let textFormat = textContent.formats.first(where: {
                        $0.uti == UTType.plainText.identifier || $0.uti == "public.utf8-plain-text"
                    }) {
                        self.selectedFormat = textFormat
                    } else {
                        self.selectedFormat = textContent.formats.first
                    }
                } else {
                    self.selectedContent = contents.first
                    self.selectedFormat = contents.first?.formats.first
                }
            }

            self.logger.info(
                "UI updated with new clipboard content: \(contents.count) content groups")
        }
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - Views

struct ContentFormatPicker: View {
    @ObservedObject var monitor: ClipboardMonitor
    let content: ClipboardContent

    var body: some View {
        Picker("Content Format", selection: $monitor.selectedFormat) {
            ForEach(content.formats, id: \.self) { format in
                Text(format.typeName)
                    .tag(format as ClipboardFormat?)
            }
        }
        .pickerStyle(.menu)
        .disabled(content.formats.isEmpty)
    }
}

struct ClipboardContentPreview: View {
    let content: ClipboardContent?
    let selectedFormat: ClipboardFormat?

    var body: some View {
        if let content = content {
            VStack {
                if content.canRenderAsText, let text = content.getTextRepresentation() {
                    ScrollView {
                        Text(text)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                } else if content.canRenderAsImage, let nsImage = NSImage(data: content.data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    }
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                } else {
                    Text("Binary data: \(content.data.count) bytes")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("No content to display")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .cornerRadius(6)
        }
    }
}

struct CurrentClipboardView: View {
    @ObservedObject var monitor: ClipboardMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Clipboard Content:")
                    .font(.headline)

                Spacer()

                if let item = monitor.currentItem, !item.contents.isEmpty,
                    let content = monitor.selectedContent
                {
                    ContentFormatPicker(monitor: monitor, content: content)
                }
            }

            if let item = monitor.currentItem, !item.contents.isEmpty {
                ClipboardContentPreview(
                    content: monitor.selectedContent, selectedFormat: monitor.selectedFormat
                )
                .frame(maxHeight: 200)
            } else {
                Text("Monitoring clipboard... Copy something!")
                    .italic()
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            }
        }
    }
}

struct HistoryItemRow: View {
    let item: ClipboardHistoryItem
    @ObservedObject var monitor: ClipboardMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with timestamp and indicators
            HStack {
                // Timestamp
                Text(formatDate(item.timestamp))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                // Type indicators
                HStack(spacing: 6) {
                    if monitor.currentItemID == item.id {
                        Label("Current", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                            .help("Current clipboard content")
                    }

                    if item.contents.contains(where: { $0.canRenderAsText }) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                    }

                    if item.contents.contains(where: { $0.canRenderAsImage }) {
                        Image(systemName: "photo")
                            .foregroundColor(.green)
                    }

                    let hasURL = item.contents.contains(where: {
                        $0.formats.contains { format in
                            format.uti.contains("url")
                        }
                    })

                    if hasURL {
                        Image(systemName: "link")
                            .foregroundColor(.purple)
                    }
                }
            }

            Divider()
                .padding(.vertical, 2)

            // Content preview
            Text(truncateString(item.textRepresentation))
                .lineLimit(2)
                .font(.system(.body))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    monitor.currentItemID == item.id
                        ? Color.green.opacity(0.5)
                        : (monitor.selectedHistoryItem?.id == item.id
                            ? Color.accentColor.opacity(0.8) : Color.gray.opacity(0.3)),
                    lineWidth: monitor.selectedHistoryItem?.id == item.id ? 2 : 1
                )
        )
        .shadow(
            color: monitor.selectedHistoryItem?.id == item.id
                ? Color.accentColor.opacity(0.3) : Color.clear,
            radius: 4
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(item.contents) { content in
                if content.formats.count == 1 {
                    Button(content.formats[0].typeName) {
                        copyToClipboard(content)
                    }
                } else {
                    Menu(getContentMenuLabel(content)) {
                        ForEach(content.formats) { format in
                            Button(format.typeName) {
                                copyToClipboard(content)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Copy All Content Types") {
                copyAllContentTypes(item)
            }
        }
    }

    private func getContentMenuLabel(_ content: ClipboardContent) -> String {
        if content.canRenderAsText {
            return "Text Content"
        } else if content.canRenderAsImage {
            return "Image Content"
        } else {
            return "Data Content (\(content.data.count) bytes)"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func truncateString(_ str: String) -> String {
        if str.count > 100 {
            return String(str.prefix(100)) + "..."
        }
        return str
    }

    private func copyToClipboard(_ content: ClipboardContent) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for format in content.formats {
            pasteboard.setData(content.data, forType: NSPasteboard.PasteboardType(format.uti))
        }
    }

    private func copyAllContentTypes(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for content in item.contents {
            for format in content.formats {
                pasteboard.setData(content.data, forType: NSPasteboard.PasteboardType(format.uti))
            }
        }
    }
}

struct HistoryListView: View {
    @ObservedObject var monitor: ClipboardMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clipboard History")
                .font(.headline)
                .padding(.bottom, 4)

            if monitor.history.isEmpty {
                Text("No clipboard history yet. Copy something!")
                    .italic()
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(monitor.history) { item in
                            HistoryItemRow(item: item, monitor: monitor)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    monitor.selectedHistoryItem = item

                                    // Update the selected content when selecting a history item
                                    if let textContent = item.contents.first(where: {
                                        $0.canRenderAsText
                                    }) {
                                        monitor.selectedContent = textContent

                                        // Update the selected format to text format if available
                                        if let textFormat = textContent.formats.first(where: {
                                            $0.uti == UTType.plainText.identifier
                                                || $0.uti == "public.utf8-plain-text"
                                        }) {
                                            monitor.selectedFormat = textFormat
                                        } else {
                                            monitor.selectedFormat = textContent.formats.first
                                        }
                                    } else {
                                        monitor.selectedContent = item.contents.first
                                        monitor.selectedFormat = item.contents.first?.formats.first
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.textBackgroundColor).opacity(0.3))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// PDFImageView leverages PDFKit as an overpowered image viewer
// The main reasons for this are the built-in handling of zoom/pan gestures
// Overall highly recommend, but there are some un-addressed PDFKit warnings
// that mean I may not be using the APIs entirely correctly, but :shrug:
struct PDFImageView: NSViewRepresentable {
    let image: NSImage
    @State private var document: PDFDocument? = nil

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()

        // Configure the view
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical

        // Start the document creation process
        createDocumentAsync()

        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Apply document when it becomes available
        if let doc = document {
            nsView.document = doc
        }
    }

    private func createDocumentAsync() {
        // Use background QoS to avoid priority inversion
        DispatchQueue.global(qos: .background).async {
            let doc = PDFDocument()
            if let page = PDFPage(image: image) {
                doc.insert(page, at: 0)
            }

            DispatchQueue.main.async {
                self.document = doc
                // No need for updateNSView to be called explicitly -
                // SwiftUI will call it when the @State variable changes
            }
        }
    }
}

struct ClipboardDetailView: View {
    @ObservedObject var monitor: ClipboardMonitor
    let item: ClipboardHistoryItem?
    @State private var selectedContentIndex = 0
    @State private var selectedFormatIndex = 0

    var body: some View {
        if let item = item {
            VStack(spacing: 8) {
                // Header
                HStack {
                    if monitor.currentItemID == item.id {
                        Label("Current Clipboard", systemImage: "circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text("Clipboard Item")
                    }

                    Text(formatDate(item.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)

                    Spacer()
                }
                .font(.headline)
                .padding([.horizontal, .top])

                // Content groups as tabs
                if !item.contents.isEmpty {
                    TabView(selection: $selectedContentIndex) {
                        ForEach(Array(item.contents.enumerated()), id: \.element.id) {
                            contentIndex, content in
                            // Get the currently selected format
                            let currentFormat = content.formats[
                                min(selectedFormatIndex, content.formats.count - 1)]

                            contentView(for: content, selectedFormat: currentFormat)
                                .tabItem {
                                    let label = getContentTabLabel(content)
                                    Text(label)
                                        .font(content.isPreviewable ? .headline : .body)
                                        .foregroundColor(
                                            content.isPreviewable ? .primary : .secondary)
                                }
                                .tag(contentIndex)
                        }
                    }
                    .onChange(of: selectedContentIndex) { newIndex in
                        // Reset format selection when changing content
                        selectedFormatIndex = 0

                        // Update the monitor's selected content and format
                        if newIndex < item.contents.count {
                            let content = item.contents[newIndex]
                            monitor.selectedContent = content
                            monitor.selectedFormat = content.formats.first
                        }
                    }
                } else {
                    Text("No content types available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Find the content containing the currently selected format
                if let selectedContent = monitor.selectedContent,
                    let selectedFormat = monitor.selectedFormat
                {
                    if let contentIndex = item.contents.firstIndex(where: {
                        $0.id == selectedContent.id
                    }) {
                        selectedContentIndex = contentIndex

                        if let formatIndex = selectedContent.formats.firstIndex(where: {
                            $0.id == selectedFormat.id
                        }) {
                            selectedFormatIndex = formatIndex
                        }
                    }
                } else if !item.contents.isEmpty {
                    // Default selection
                    selectedContentIndex = 0
                    selectedFormatIndex = 0
                    monitor.selectedContent = item.contents[0]
                    monitor.selectedFormat = item.contents[0].formats[0]
                }
            }
        } else {
            VStack {
                Image(systemName: "clipboard")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                    .padding(.bottom)

                Text("Select a clipboard item to view details")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // Generate better, more specific tab labels for content
    private func getContentTabLabel(_ content: ClipboardContent) -> String {
        if content.formats.count == 1 {
            return content.formats[0].typeName
        }

        // Create more specific labels for content with multiple formats
        if content.canRenderAsText {
            // For text types, include the specific formats
            let formatNames = content.formats.prefix(2).map {
                $0.typeName.replacingOccurrences(of: " Text", with: "")
            }
            let additionalCount = content.formats.count > 2 ? " +\(content.formats.count - 2)" : ""
            return "Text (\(formatNames.joined(separator: "/"))\(additionalCount))"
        } else if content.canRenderAsImage {
            // For image types, include the specific formats
            let formatNames = content.formats.prefix(2).map {
                $0.typeName.replacingOccurrences(of: " Image", with: "")
            }
            let additionalCount = content.formats.count > 2 ? " +\(content.formats.count - 2)" : ""
            return "Image (\(formatNames.joined(separator: "/"))\(additionalCount))"
        } else {
            // For other types, show data size
            return "Data (\(content.data.count) bytes)"
        }
    }

    @ViewBuilder
    private func contentView(for content: ClipboardContent, selectedFormat: ClipboardFormat)
        -> some View
    {
        VStack {
            // Format selector (only show if multiple formats available)
            if content.formats.count > 1 {
                Menu {
                    ForEach(Array(content.formats.enumerated()), id: \.element.id) {
                        index, format in
                        Button(format.typeName) {
                            selectedFormatIndex = index
                            monitor.selectedFormat = format
                        }
                    }
                } label: {
                    HStack {
                        Text("Format: \(selectedFormat.typeName)")
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }

            // Preview section
            Group {
                if content.canRenderAsText, let text = content.getTextRepresentation() {
                    ScrollView {
                        Text(text)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else if content.canRenderAsImage, let nsImage = NSImage(data: content.data) {
                    // Use simplified PDFKit for image viewing with pinch-to-zoom
                    PDFImageView(image: nsImage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        Text("Binary data: \(content.data.count) bytes")
                            .foregroundColor(.secondary)
                            .padding()

                        // ASCII interpretation for small binary data
                        if content.data.count < 1024 {
                            Divider()

                            VStack(alignment: .leading) {
                                Text("ASCII Interpretation:")
                                    .font(.subheadline)
                                    .padding(.bottom, 4)

                                ScrollView {
                                    Text(asciiRepresentation(of: content.data))
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(6)

            // Simplified metadata section
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Format", value: selectedFormat.typeName)
                DetailRow(label: "UTI", value: selectedFormat.uti)
                DetailRow(label: "Size", value: "\(content.data.count) bytes")
                DetailRow(
                    label: "Available Formats",
                    value: content.formats.map { $0.typeName }.joined(separator: ", "))
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
            .cornerRadius(6)
        }
        .padding()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func asciiRepresentation(of data: Data) -> String {
        var result = ""
        let bytes = [UInt8](data)

        for (index, byte) in bytes.enumerated() {
            // Add newline every 16 bytes
            if index % 16 == 0 && index > 0 {
                result += "\n"
            }

            // Add readable character or dot for non-printable
            if byte >= 32 && byte <= 126 {
                result += String(format: "%c", byte)
            } else {
                result += "."
            }

            // Add space between characters
            if index % 16 != 15 && index != bytes.count - 1 {
                result += " "
            }
        }

        return result
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 120, alignment: .leading)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ContentView: View {
    @StateObject private var clipboardMonitor = ClipboardMonitor()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 10) {
                HistoryListView(monitor: clipboardMonitor)
            }
            .padding()
            .navigationTitle("spaperclip")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        clipboardMonitor.clearHistory()
                    }) {
                        Label("Clear History", systemImage: "trash")
                    }
                    .help("Clear clipboard history")
                    .keyboardShortcut("K", modifiers: [.command, .shift])
                }
            }
        } detail: {
            ClipboardDetailView(
                monitor: clipboardMonitor,
                item: clipboardMonitor.selectedHistoryItem
            )
        }
        .onDisappear {
            clipboardMonitor.stopMonitoring()
        }
    }
}

// MARK: - App

/// Main application structure
@main
struct ClipboardViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Clipboard") {
                Button("Clear History") {
                    // TODO
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
            }
        }
    }
}
