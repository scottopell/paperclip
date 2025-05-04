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
        selectedHistoryItem = nil
        selectedContent = nil
        selectedFormat = nil
    }

    // MARK: - Selection Management

    /// Selects a history item and updates content/format selections accordingly
    func selectHistoryItem(_ item: ClipboardHistoryItem?) {
        selectedHistoryItem = item

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

// MARK: - Views

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
            contentCard
                .contentShape(Rectangle())
                .contextMenu {
                    contextMenu
                }
        }
        
        // MARK: - Component Parts
        
        private var contentCard: some View {
            VStack(alignment: .leading, spacing: 4) {
                headerRow
                
                Divider()
                    .padding(.vertical, 2)
                
                contentPreview
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
            .cornerRadius(6)
            .overlay(cardBorder)
            .shadow(
                color: monitor.selectedHistoryItem?.id == item.id
                    ? Color.accentColor.opacity(0.3) : Color.clear,
                radius: 4
            )
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        
        private var headerRow: some View {
            HStack(spacing: 4) {
                Text(formatDate(item.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                typeIndicators
            }
        }
        
        private var contentPreview: some View {
            Text(item.textRepresentation.map { truncateString($0) } ?? "(Unsupported format)")
                .font(.system(.caption))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        private var cardBorder: some View {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    monitor.currentItemID == item.id
                        ? Color.green.opacity(0.5)
                        : (monitor.selectedHistoryItem?.id == item.id
                            ? Color.accentColor.opacity(0.8) : Color.gray.opacity(0.3)),
                    lineWidth: monitor.selectedHistoryItem?.id == item.id ? 2 : 1
                )
        }

    var typeIndicators: some View {
        HStack(spacing: 4) {
            if monitor.currentItemID == item.id {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
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
    var contextMenu: some View {
        HStack {
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
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""

    // Add a timer publisher for debouncing
    private let searchTextPublisher = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    var filteredHistory: [ClipboardHistoryItem] {
        if debouncedSearchText.isEmpty {
            return monitor.history
        } else {
            return monitor.history.filter { item in
                guard let itemText = item.textRepresentation else {
                    return false;
                }
                return itemText.localizedCaseInsensitiveContains(debouncedSearchText)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Search field - always at the top
            HStack {
                // Use NSSearchField for native macOS look and feel
                SearchField(
                    searchText: $searchText,
                    placeholder: "Search clipboard history...",
                    onSearchTextChanged: { newText in
                        searchTextPublisher.send(newText)
                    }
                )

                Spacer()

                Button(action: {
                    searchText = ""
                    searchTextPublisher.send("")
                    monitor.clearHistory()
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Clear History")
            }
            .padding(.bottom, 4)

            // Always show the ScrollView container regardless of content
            ScrollView {
                if filteredHistory.isEmpty {
                    VStack {
                        if monitor.history.isEmpty {
                            Text("No clipboard history yet. Copy something!")
                                .italic()
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No results matching '\(debouncedSearchText)'")
                                .italic()
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(4)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredHistory) { item in
                            HistoryItemRow(item: item, monitor: monitor)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    monitor.selectHistoryItem(item)
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
            .cornerRadius(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)  // Align to top
        .padding(4)
        .onAppear {
            // Setup the debounced search
            cancellable =
                searchTextPublisher
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .sink { value in
                    debouncedSearchText = value
                }
        }
    }
}
// Native macOS search field wrapper
struct SearchField: NSViewRepresentable {
    @Binding var searchText: String
    var placeholder: String
    var onSearchTextChanged: (String) -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        nsView.stringValue = searchText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            if let searchField = notification.object as? NSSearchField {
                let searchText = searchField.stringValue
                parent.searchText = searchText
                parent.onSearchTextChanged(searchText)
            }
        }
    }
}

struct ClipboardDetailView: View {
    @ObservedObject var monitor: ClipboardMonitor
    let item: ClipboardHistoryItem?

    var body: some View {
        if let item = item {
            VStack(spacing: 4) {
                // Header
                HStack {
                    if monitor.currentItemID == item.id {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Current")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Text(formatDate(item.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        copyAllContentTypes(item)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy to Clipboard")
                }
                .padding([.horizontal, .top], 4)

                // Content groups as tabs
                if !item.contents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(item.contents) { content in
                                Button(action: {
                                    monitor.selectContent(content)
                                }) {
                                    HStack(spacing: 2) {
                                        contentTypeIcon(for: content)
                                            .font(.caption)

                                        Text(getContentTabLabel(content))
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(
                                        monitor.selectedContent?.id == content.id
                                            ? Color.accentColor.opacity(0.2) : Color.clear
                                    )
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 4)
                        }
                        .padding(.bottom, 4)
                    }

                    // Format picker - only show if the selected content has multiple formats
                    if let selectedContent = monitor.selectedContent,
                        selectedContent.formats.count > 1
                    {
                        HStack {
                            Text("Format:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker(
                                "",
                                selection: Binding<ClipboardFormat?>(
                                    get: { monitor.selectedFormat },
                                    set: { monitor.selectFormat($0) }
                                )
                            ) {
                                ForEach(selectedContent.formats) { format in
                                    Text(format.typeName).tag(format as ClipboardFormat?)
                                }
                            }
                            .pickerStyle(.menu)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    }

                    // Content view
                    if let selectedContent = monitor.selectedContent,
                        let selectedFormat = monitor.selectedFormat
                    {
                        contentView(for: selectedContent, selectedFormat: selectedFormat)
                    } else {
                        Text("No content selected")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else {
                    Text("No content types available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Set the monitor's selected history item when the view appears
                monitor.selectHistoryItem(item)
            }
            .onChange(of: item) { newItem in
                // Update selection when the item changes
                monitor.selectHistoryItem(newItem)
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

    @ViewBuilder
    private func contentTypeIcon(for content: ClipboardContent) -> some View {
        if content.canRenderAsText {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
        } else if content.canRenderAsImage {
            Image(systemName: "photo")
                .foregroundColor(.green)
        } else {
            Image(systemName: "doc.binary")
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private func contentView(for content: ClipboardContent, selectedFormat: ClipboardFormat)
        -> some View
    {
        VStack(spacing: 4) {
            // Preview section
            Group {
                if content.canRenderAsText, let text = content.getTextRepresentation() {
                    ScrollView {
                        Text(text)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else if content.canRenderAsImage, let nsImage = NSImage(data: content.data) {
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

            // Integrated metadata section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("UTI:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(selectedFormat.uti)
                                .font(.caption2)
                                .textSelection(.enabled)
                        }

                        HStack {
                            Text("Size:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(content.data.count) bytes")
                                .font(.caption2)
                        }
                    }

                    Spacer()

                    // Show alternative formats as buttons
                    if content.formats.count > 1 {
                        VStack(alignment: .trailing) {
                            Text("Other formats:")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            HStack {
                                ForEach(content.formats.filter { $0.id != selectedFormat.id }) {
                                    format in
                                    Button(format.typeName) {
                                        monitor.selectFormat(format)
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.link)
                                }
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
            .cornerRadius(6)
        }
        .padding(8)
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
            HistoryListView(monitor: clipboardMonitor)
        } detail: {
            ClipboardDetailView(
                monitor: clipboardMonitor,
                item: clipboardMonitor.selectedHistoryItem
            )
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
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
