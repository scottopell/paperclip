//
//  HistoryList.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//
// TODO add support for using arrow up/down keys to
// select different elements in the HistoryList and
// have the "enter" action be to re-copy all content
// types. have shift+enter be to re-copy only the
// plain text, if there is no plain text then
// do not put anything on the clipboard

import SwiftUI
import Combine

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
