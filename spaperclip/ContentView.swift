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
    @Published var currentItemID: UUID?
    
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
            
            let newItem = ClipboardHistoryItem(
                timestamp: Date(),
                changeCount: pasteboard.changeCount,
                dataTypes: dataTypes
            )
            
            // Update current item reference
            self.currentItem = newItem
            // Set the current item ID
            self.currentItemID = newItem.id
            
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
    @ObservedObject var monitor: ClipboardMonitor
    
    let dataTypes: [ClipboardDataType]
    
    var body: some View {
        Picker("Content Type", selection: $monitor.selectedType) {
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
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                } else if dataType.canRenderAsImage, let nsImage = NSImage(data: dataType.data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    }
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                } else {
                    Text("Binary data: \(dataType.data.count) bytes")
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
                
                if let item = monitor.currentItem, !item.dataTypes.isEmpty {
                    ContentTypePicker(monitor: monitor, dataTypes: item.dataTypes)
                }
            }
            
            if let item = monitor.currentItem {
                ClipboardContentPreview(dataType: monitor.selectedType)
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
                .stroke(monitor.currentItemID == item.id ? Color.green.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
        if str.count > 100 {
            return String(str.prefix(100)) + "..."
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
                                    // Update the selected type when selecting a history item
                                    if let textType = item.dataTypes.first(where: { $0.canRenderAsText }) {
                                        monitor.selectedType = textType
                                    } else {
                                        monitor.selectedType = item.dataTypes.first
                                    }
                                }
                                .background(
                                    monitor.selectedHistoryItem?.id == item.id ?
                                        Color.accentColor.opacity(0.1) : Color.clear
                                )
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
struct ClipboardDetailView: View {
    @ObservedObject var monitor: ClipboardMonitor

    let item: ClipboardHistoryItem?
    @State private var selectedTab = 0
    
    var body: some View {
        if let item = item {
            VStack(spacing: 0) {
                // Header with type selector
                HStack {
                    if monitor.currentItemID == item.id {
                        Label("Current Clipboard Content", systemImage: "circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text("Clipboard Item Details")
                    }
                    
                    Spacer()
                    
                    if let item = monitor.currentItem, !item.dataTypes.isEmpty {
                        ContentTypePicker(monitor: monitor, dataTypes: item.dataTypes)
                    }                }
                .font(.headline)
                .padding([.horizontal, .top])
                
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("Preview").tag(0)
                    Text("Details").tag(1)
                    Text("Actions").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                
                Divider()
                    .padding(.top, 8)
                
                // Tab content
                TabView(selection: $selectedTab) {
                    // Preview Tab
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let dataType = monitor.selectedType {
                                ClipboardContentPreview(dataType: dataType)
                                    .frame(minHeight: 300)
                            } else {
                                Text("No content type selected")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            }
                        }
                        .padding()
                    }
                    .tag(0)
                    
                    // Details Tab
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Metadata section
                            GroupBox("Metadata") {
                                VStack(alignment: .leading, spacing: 8) {
                                    DetailRow(label: "Timestamp", value: formatDate(item.timestamp))
                                    DetailRow(label: "Available Types", value: "\(item.dataTypes.count)")
                                    
                                    if let dataType = monitor.selectedType {
                                        Divider()
                                        
                                        DetailRow(label: "Type", value: dataType.typeName)
                                        DetailRow(label: "UTI", value: dataType.uti)
                                        DetailRow(label: "Size", value: "\(dataType.data.count) bytes")
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                    .tag(1)
                    
                    // Actions Tab
                    VStack(spacing: 20) {
                        if let dataType = monitor.selectedType {
                            Button(action: {
                                copyToClipboard(dataType)
                            }) {
                                Label("Copy This Format (\(dataType.typeName))", systemImage: "doc.on.doc")
                                    .frame(maxWidth: 300)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        
                        Button(action: {
                            copyAllDataTypes(item)
                        }) {
                            Label("Copy All Formats", systemImage: "rectangle.on.rectangle")
                                .frame(maxWidth: 300)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        
                        Spacer()
                    }
                    .padding()
                    .tag(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// Helper view for displaying detail rows
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
