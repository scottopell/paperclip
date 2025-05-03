import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import os

// MARK: - Models

struct ClipboardDataType: Identifiable, Hashable {
    let id = UUID()
    let uti: String
    let data: Data
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
            "public.html"
        ]
        return textTypes.contains(uti)
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
            "com.adobe.pdf"
        ]
        return imageTypes.contains(uti)
    }
    
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
    
    func getTextRepresentation() -> String? {
        if uti == UTType.plainText.identifier || uti == "public.utf8-plain-text" {
            return String(data: data, encoding: .utf8)
        } else if uti == UTType.rtf.identifier || uti == "public.rtf" {
            if let attributedString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                return attributedString.string
            }
        } else if uti == UTType.html.identifier || uti == "public.html" {
            if let attributedString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                return attributedString.string
            }
        } else if uti == UTType.url.identifier || uti == "public.url" {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(uti)
    }
    
    static func == (lhs: ClipboardDataType, rhs: ClipboardDataType) -> Bool {
        return lhs.id == rhs.id && lhs.uti == rhs.uti
    }
}

struct ClipboardHistoryItem: Identifiable, Equatable, Hashable {
    let id = UUID()
    let timestamp: Date
    let changeCount: Int
    var dataTypes: [ClipboardDataType]
    var isLive: Bool = false
    
    var textRepresentation: String {
        for dataType in dataTypes {
            if let text = dataType.getTextRepresentation() {
                return text
            }
        }
        return "No text representation available"
    }
    
    var hasImageRepresentation: Bool {
        return dataTypes.contains { $0.canRenderAsImage }
    }
    
    static func == (lhs: ClipboardHistoryItem, rhs: ClipboardHistoryItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - View Model

class ClipboardMonitor: ObservableObject {
    @Published var currentItem: ClipboardHistoryItem?
    @Published var history: [ClipboardHistoryItem] = []
    @Published var selectedType: ClipboardDataType?
    @Published var selectedHistoryItem: ClipboardHistoryItem?
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let logger = Logger(subsystem: "com.scottopell.spaperclip", category: "ClipboardMonitor")
    
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
        "com.apple.finder.drag.clipping"
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
        
        var dataTypes: [ClipboardDataType] = []
        
        for type in knownTypes {
            if availableTypes.contains(NSPasteboard.PasteboardType(type)),
               let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type)) {
                
                let description = type == "public.utf8-plain-text"
                    ? (String(data: data, encoding: .utf8) ?? "Unknown text data")
                    : "Binary data (\(data.count) bytes)"
                
                let dataType = ClipboardDataType(
                    uti: type,
                    data: data,
                    description: description
                )
                dataTypes.append(dataType)
            }
        }
        
        // Check for any other types
        for type in availableTypes {
            let typeString = type.rawValue
            if !knownTypes.contains(typeString),
               let data = pasteboard.data(forType: type) {
                
                let dataType = ClipboardDataType(
                    uti: typeString,
                    data: data,
                    description: "Binary data (\(data.count) bytes)"
                )
                dataTypes.append(dataType)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update isLive flag on previous current item
            if let oldCurrentIndex = self.history.firstIndex(where: { $0.isLive }) {
                self.history[oldCurrentIndex].isLive = false
            }
            
            // Create new history item
            var newItem = ClipboardHistoryItem(
                timestamp: Date(),
                changeCount: pasteboard.changeCount,
                dataTypes: dataTypes,
                isLive: true
            )
            
            // Update current item
            self.currentItem = newItem
            
            if !dataTypes.isEmpty {
                // Insert at beginning (most recent first)
                self.history.insert(newItem, at: 0)
                
                // Limit history size
                if self.history.count > 100 {
                    self.history = Array(self.history.prefix(100))
                }
                
                // Set initially selected type to text if available
                if let textType = dataTypes.first(where: { $0.canRenderAsText }) {
                    self.selectedType = textType
                } else {
                    self.selectedType = dataTypes.first
                }
            }
            
            self.logger.info("UI updated with new clipboard content: \(dataTypes.count) data types")
        }
    }
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Views

struct ContentTypePicker: View {
    let dataTypes: [ClipboardDataType]
    @Binding var selectedType: ClipboardDataType?
    
    var body: some View {
        Picker("Content Type", selection: $selectedType) {
            ForEach(dataTypes, id: \.self) { dataType in
                Text(dataType.typeName)
                    .tag(dataType as ClipboardDataType?)
            }
        }
        .pickerStyle(.menu)
        .disabled(dataTypes.isEmpty)
    }
}

struct ClipboardContentPreview: View {
    let dataType: ClipboardDataType?
    
    var body: some View {
        if let dataType = dataType {
            VStack {
                if dataType.canRenderAsText, let text = dataType.getTextRepresentation() {
                    ScrollView {
                        Text(text)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else if dataType.canRenderAsImage, let nsImage = NSImage(data: dataType.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Binary data: \(dataType.data.count) bytes")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        } else {
            Text("No content to display")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
        }
    }
}

struct CurrentClipboardView: View {
    let item: ClipboardHistoryItem?
    @Binding var selectedType: ClipboardDataType?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Current Clipboard Content:")
                    .font(.headline)
                
                Spacer()
                
                if let item = item, !item.dataTypes.isEmpty {
                    ContentTypePicker(dataTypes: item.dataTypes, selectedType: $selectedType)
                }
            }
            
            if let item = item {
                ClipboardContentPreview(dataType: selectedType)
            } else {
                Text("Monitoring clipboard... Copy something!")
                    .italic()
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }
}

struct HistoryItemRow: View {
    let item: ClipboardHistoryItem
    
    var body: some View {
        HStack {
            // Timestamp column
            Text(formatDate(item.timestamp))
                .frame(width: 150, alignment: .leading)
                .font(.system(.body, design: .monospaced))
            
            // Type indicators
            HStack(spacing: 4) {
                if item.isLive {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .help("Current clipboard content")
                }
                
                if item.dataTypes.contains(where: { $0.canRenderAsText }) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.blue)
                }
                
                if item.dataTypes.contains(where: { $0.canRenderAsImage }) {
                    Image(systemName: "photo")
                        .foregroundColor(.green)
                }
                
                if item.dataTypes.contains(where: { $0.uti.contains("url") }) {
                    Image(systemName: "link")
                        .foregroundColor(.purple)
                }
            }
            .frame(width: 80, alignment: .leading)
            
            // Content preview
            Text(truncateString(item.textRepresentation))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            ForEach(item.dataTypes) { dataType in
                Button(dataType.typeName) {
                    copyToClipboard(dataType)
                }
            }
            
            Divider()
            
            Button("Copy All Data Types") {
                copyAllDataTypes(item)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func truncateString(_ str: String) -> String {
        if str.count > 50 {
            return String(str.prefix(50)) + "..."
        }
        return str
    }
    
    private func copyToClipboard(_ dataType: ClipboardDataType) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(dataType.data, forType: NSPasteboard.PasteboardType(dataType.uti))
    }
    
    private func copyAllDataTypes(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        for dataType in item.dataTypes {
            pasteboard.setData(dataType.data, forType: NSPasteboard.PasteboardType(dataType.uti))
        }
    }
}

struct ClipboardDetailView: View {
    let item: ClipboardHistoryItem?
    @Binding var selectedType: ClipboardDataType?
    
    var body: some View {
        if let item = item {
            VStack {
                HStack {
                    if item.isLive {
                        Label("Current Clipboard Content", systemImage: "circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text("Clipboard Item Details")
                    }
                    
                    Spacer()
                    
                    ContentTypePicker(dataTypes: item.dataTypes, selectedType: $selectedType)
                }
                .font(.headline)
                .padding(.bottom, 5)
                
                Form {
                    Section("Metadata") {
                        LabeledContent("Timestamp") {
                            Text(formatDate(item.timestamp))
                        }
                        
                        LabeledContent("Available Types") {
                            Text("\(item.dataTypes.count)")
                        }
                    }
                    
                    Section("Content Preview") {
                        ClipboardContentPreview(dataType: selectedType)
                            .frame(height: 300)
                    }
                    
                    if let dataType = selectedType {
                        Section("Type Details") {
                            LabeledContent("Type") {
                                Text(dataType.typeName)
                            }
                            
                            LabeledContent("UTI") {
                                Text(dataType.uti)
                            }
                            
                            LabeledContent("Size") {
                                Text("\(dataType.data.count) bytes")
                            }
                            
                            Button("Copy This Format") {
                                copyToClipboard(dataType)
                            }
                            
                            Button("Copy All Formats") {
                                copyAllDataTypes(item)
                            }
                        }
                    }
                }
            }
            .padding()
        } else {
            Text("Select a clipboard item to view details")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func copyToClipboard(_ dataType: ClipboardDataType) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(dataType.data, forType: NSPasteboard.PasteboardType(dataType.uti))
    }
    
    private func copyAllDataTypes(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        for dataType in item.dataTypes {
            pasteboard.setData(dataType.data, forType: NSPasteboard.PasteboardType(dataType.uti))
        }
    }
}

struct HistoryListView: View {
    let history: [ClipboardHistoryItem]
    @Binding var selectedHistoryItem: ClipboardHistoryItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Clipboard History:")
                .font(.headline)
            
            if history.isEmpty {
                Text("No clipboard history yet. Copy something!")
                    .italic()
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(history, selection: $selectedHistoryItem) { item in
                    HistoryItemRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedHistoryItem = item
                        }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var clipboardMonitor = ClipboardMonitor()
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 10) {
                // Current clipboard content
                CurrentClipboardView(
                    item: clipboardMonitor.currentItem,
                    selectedType: $clipboardMonitor.selectedType
                )
                .frame(height: 200)
                
                Divider()
                    .padding(.vertical, 5)
                
                // Clipboard history
                HistoryListView(
                    history: clipboardMonitor.history,
                    selectedHistoryItem: $clipboardMonitor.selectedHistoryItem
                )
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
                item: clipboardMonitor.selectedHistoryItem,
                selectedType: $clipboardMonitor.selectedType
            )
        }
        .onDisappear {
            clipboardMonitor.stopMonitoring()
        }
    }
}

