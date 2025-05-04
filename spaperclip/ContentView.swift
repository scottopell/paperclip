import AppKit
import SwiftUI

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

