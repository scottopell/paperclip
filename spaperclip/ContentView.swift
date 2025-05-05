import AppKit
import SwiftUI

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
            Text(Utilities.formatDate(item.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            typeIndicators
        }
    }

    private var contentPreview: some View {
        Text(item.textRepresentation.map { $0.truncated() } ?? "(Unsupported format)")
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
                        Utilities.copyToClipboard(content)
                    }
                } else {
                    Menu(getContentMenuLabel(content)) {
                        ForEach(content.formats) { format in
                            Button(format.typeName) {
                                Utilities.copyToClipboard(content)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Copy All Content Types") {
                Utilities.copyAllContentTypes(from: item)
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

}

struct ContentView: View {
    @StateObject private var clipboardMonitor = ClipboardMonitor()

    var body: some View {
        NavigationSplitView {
            HistoryListView(monitor: clipboardMonitor)
        } detail: {
            ClipboardDetailView(
                monitor: clipboardMonitor,
            )
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        .onDisappear {
            clipboardMonitor.stopMonitoring()
        }
    }
}
