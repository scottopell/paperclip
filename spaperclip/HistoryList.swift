//
//  HistoryList.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.

import Combine
import SwiftUI

struct HistoryItemRow: View {
    let item: ClipboardHistoryItem
    @ObservedObject var monitor: ClipboardMonitor
    @State private var previewText: String = "(Loading...)"

    var body: some View {
        contentCard
            .contentShape(Rectangle())
            .contextMenu {
                contextMenu
            }
            .task {
                // Load text preview efficiently from first 100 characters
                await loadPreviewText()
            }
    }

    private func loadPreviewText() async {
        // Check each content in the item for text representation
        for content in item.contents {
            // Try to get just the first 100 characters using efficient chunking
            if let (chunk, _) = content.getTextChunk(offset: 0, length: 100) {
                // We found text content, use it for the preview
                if chunk.isEmpty {
                    self.previewText = "(Empty)"
                } else if chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.previewText = "(Whitespace only)"
                } else {
                    self.previewText = chunk
                }
                return
            }
        }

        // If we get here, no text representation was found
        self.previewText = "(Unsupported format)"
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

            if let sourceApp = item.sourceApplication?.applicationName, !sourceApp.isEmpty {
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(sourceApp)
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
            }

            Spacer()

            typeIndicators
        }
    }

    private var contentPreview: some View {
        HStack(spacing: 8) {
            // Source application icon
            if let nsImage = monitor.getIconForHistoryItem(item) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .help(monitor.getSourceAppNameForHistoryItem(item))
            }

            Text(previewText)
                .font(.system(.caption))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        Group {
            if let sourceApp = item.sourceApplication?.applicationName, !sourceApp.isEmpty {
                Section {
                    Text("From: \(sourceApp)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
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

@available(macOS 14.0, *)
struct HistoryListView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    var showSearchBar: Bool = true

    // Add a timer publisher for debouncing
    private let searchTextPublisher = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    var filteredHistory: [ClipboardHistoryItem] {
        if debouncedSearchText.isEmpty {
            return monitor.history
        } else {
            return monitor.history.filter { item in
                guard let itemText = item.textRepresentation else {
                    return false
                }
                return itemText.localizedCaseInsensitiveContains(debouncedSearchText)
            }
        }
    }

    // Get the selected item directly from the monitor
    private var selectedItem: ClipboardHistoryItem? {
        return monitor.selectedHistoryItem
    }

    // Get the previous item in the filtered history
    private var previousItem: ClipboardHistoryItem? {
        guard let currentItem = selectedItem,
            let currentIndex = filteredHistory.firstIndex(where: { $0.id == currentItem.id }),
            currentIndex > 0
        else {
            return nil
        }
        return filteredHistory[currentIndex - 1]
    }

    // Get the next item in the filtered history
    private var nextItem: ClipboardHistoryItem? {
        guard let currentItem = selectedItem,
            let currentIndex = filteredHistory.firstIndex(where: { $0.id == currentItem.id }),
            currentIndex < filteredHistory.count - 1
        else {
            return nil
        }
        return filteredHistory[currentIndex + 1]
    }

    // Select a specific item directly using monitor
    private func selectItem(_ item: ClipboardHistoryItem) {
        monitor.selectHistoryItem(item)
    }

    // Select first item in the list
    private func selectFirstItem() {
        guard let firstItem = filteredHistory.first else { return }
        selectItem(firstItem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Search field - always at the top
            if showSearchBar {
                HStack {
                    // Use NSSearchField for native macOS look and feel
                    SearchField(
                        searchText: $searchText,
                        placeholder: "Search clipboard history...",
                        onSearchTextChanged: { newText in
                            searchTextPublisher.send(newText)
                        }
                    )
                }
                .padding(.bottom, 4)
            }

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
                        ForEach(Array(filteredHistory.enumerated()), id: \.element.id) {
                            index, item in
                            HistoryItemRow(item: item, monitor: monitor)
                                .contentShape(Rectangle())
                                .background(
                                    monitor.selectedHistoryItem?.id == item.id
                                        ? Color.accentColor.opacity(0.2) : Color.clear
                                )
                                .cornerRadius(4)
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
                    // Reset selection when search changes
                    if !filteredHistory.isEmpty {
                        selectFirstItem()
                    } else {
                        monitor.selectHistoryItem(nil)
                    }
                }

            // Initialize selection if history is not empty
            if !filteredHistory.isEmpty && monitor.selectedHistoryItem == nil {
                selectFirstItem()
            }
        }
        .onKeyPress(.upArrow) {
            if let prevItem = previousItem {
                selectItem(prevItem)
                return .handled
            } else if !filteredHistory.isEmpty && selectedItem == nil {
                selectFirstItem()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow) {
            if let nextItem = nextItem {
                selectItem(nextItem)
                return .handled
            } else if !filteredHistory.isEmpty && selectedItem == nil {
                selectFirstItem()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            // TODO confirm this works, I'm not seeing any clipboard updates
            guard let item = selectedItem else {
                return .ignored
            }

            if NSEvent.modifierFlags.contains(.shift) {
                // Shift+Enter: Copy only plain text if available
                if item.textRepresentation != nil {
                    monitor.copyPlainTextOnly(item)
                }
            } else {
                // Enter: Copy all content types
                monitor.selectHistoryItem(item)
            }
            return .handled
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
