import AppKit
import SwiftUI

enum QuickSearchQuery {
    static func results(
        in history: [ClipboardHistoryItem], matching query: String
    ) -> [ClipboardHistoryItem] {
        ClipboardHistoryFilter.matching(history, searchText: query)
    }
}

struct QuickSearchView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var manager: QuickSearchManager
    @State private var searchText: String = ""
    @State private var filteredHistory: [ClipboardHistoryItem] = []
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFieldFocused: Bool


    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search clipboard history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($isSearchFieldFocused)
                    .accessibilityIdentifier("quick-search.field")
                    .onChange(of: searchText) { _, newValue in
                        applyQuery(newValue)
                    }
                    .onKeyPress(.upArrow) {
                        moveSelection(by: -1)
                    }
                    .onKeyPress(.downArrow) {
                        moveSelection(by: 1)
                    }
                    .onKeyPress(.return) {
                        restoreSelection()
                    }
                    .onKeyPress(.escape) {
                        manager.hideQuickSearch()
                        return .handled
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        colorScheme == .dark
                            ? Color(NSColor.controlBackgroundColor)
                            : Color(NSColor.textBackgroundColor))
            )
            .padding([.horizontal, .top], 16)

            // History list
            HistoryListView(
                monitor: monitor,
                showSearchBar: false,
                externalSearchText: searchText,
                filteredHistoryOverride: filteredHistory,
                onItemCopied: { manager.hideQuickSearch() },
                accessibilityPrefix: "quick-search"
            )
            .padding([.horizontal, .bottom], 16)
            .padding(.top, 8)
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
        )
        .frame(minWidth: 600, minHeight: 400)
        .onChange(of: monitor.history) { _, _ in
            applyQuery(searchText)
        }
        .task(id: manager.presentationID) {
            if searchText.isEmpty {
                applyQuery("")
            } else {
                searchText = ""
            }
            isSearchFieldFocused = false
            await Task.yield()
            isSearchFieldFocused = true
        }
        .onKeyPress(.escape) {
            manager.hideQuickSearch()
            return .handled
        }
    }

    private func applyQuery(_ query: String) {
        filteredHistory = QuickSearchQuery.results(
            in: monitor.history, matching: query
        )
        monitor.selectHistoryItem(filteredHistory.first)
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !filteredHistory.isEmpty else { return .handled }

        let currentIndex = monitor.selectedHistoryItem.flatMap { selected in
            filteredHistory.firstIndex(where: { $0.id == selected.id })
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), filteredHistory.count - 1)
        monitor.selectHistoryItem(filteredHistory[nextIndex])
        return .handled
    }

    private func restoreSelection() -> KeyPress.Result {
        guard let selected = monitor.selectedHistoryItem,
            filteredHistory.contains(where: { $0.id == selected.id })
        else {
            return .handled
        }

        let copied = NSEvent.modifierFlags.contains(.shift)
            ? monitor.copyPlainTextOnly(selected)
            : monitor.copyAllContentTypes(selected)
        if copied { manager.hideQuickSearch() }
        return .handled
    }
}

// Helper view to create NSVisualEffectView in SwiftUI
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
