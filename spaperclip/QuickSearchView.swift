import AppKit
import Combine
import SwiftUI

struct QuickSearchView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var manager: QuickSearchManager
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFieldFocused: Bool

    // Add a timer publisher for debouncing
    private let searchTextPublisher = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    private var filteredHistory: [ClipboardHistoryItem] {
        ClipboardHistoryFilter.matching(monitor.history, searchText: debouncedSearchText)
    }

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
                        searchTextPublisher.send(newValue)
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
                        searchTextPublisher.send("")
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
                externalSearchText: debouncedSearchText,
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
        .onAppear {
            cancellable =
                searchTextPublisher
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .sink { value in
                    debouncedSearchText = value
                    let matches = ClipboardHistoryFilter.matching(
                        monitor.history,
                        searchText: value
                    )
                    monitor.selectHistoryItem(matches.first)
                }
        }
        .task(id: manager.presentationID) {
            searchText = ""
            debouncedSearchText = ""
            monitor.selectHistoryItem(monitor.history.first)
            isSearchFieldFocused = false
            await Task.yield()
            isSearchFieldFocused = true
        }
        .onDisappear {
            cancellable?.cancel()
            cancellable = nil
        }
        .onKeyPress(.escape) {
            manager.hideQuickSearch()
            return .handled
        }
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
