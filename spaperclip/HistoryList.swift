//
//  HistoryList.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.

import Combine
import SwiftUI

@available(macOS 14.0, *)
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
