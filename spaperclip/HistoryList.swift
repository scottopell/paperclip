//
//  HistoryList.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.

import Combine
import SwiftUI

enum ClipboardHistoryPreview {
    static func fallbackText(for item: ClipboardHistoryItem) -> String {
        if item.hasImageRepresentation { return "(Image)" }
        if item.contents.contains(where: {
            $0.usesLocalHTMLText && $0.data.count > LocalHTMLText.maximumImportBytes
        }) { return "(HTML too large to preview)" }
        return "(Unsupported format)"
    }
}

struct CurrentClipboardBadge: View {
    var body: some View {
        Label("Current", systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.green)
            .help("Current clipboard content")
            .accessibilityLabel("Current clipboard item")
    }
}

struct HistoryItemRow: View {
    let item: ClipboardHistoryItem
    @ObservedObject var monitor: ClipboardMonitor
    @State private var previewText: String = "(Loading...)"
    @State private var sourceIcon: NSImage?
    @State private var copyError: String?

    var body: some View {
        contentCard
            .contentShape(Rectangle())
            .contextMenu {
                contextMenu
            }
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(accessibilitySummary)
                    .accessibilityValue(copyError ?? "")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(
                        monitor.selectedHistoryItem?.id == item.id ? .isSelected : []
                    )
                    .allowsHitTesting(false)
            }
            .task(id: item.id) {
                previewText = "(Loading...)"
                copyError = nil
                for content in item.contents {
                    if let chunk = await ClipboardPreviewText.chunk(for: content, length: 100) {
                        guard !Task.isCancelled else { return }
                        if chunk.isEmpty { previewText = "(Empty)" }
                        else if chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            previewText = "(Whitespace only)"
                        } else { previewText = chunk }
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                previewText = ClipboardHistoryPreview.fallbackText(for: item)
            }
            .task(id: item.id) {
                sourceIcon = nil
                guard let bundleID = item.sourceApplication?.bundleIdentifier else { return }
                let icon = await Task.detached(priority: .utility) {
                    SourceApplicationIconCache.shared.icon(for: bundleID)
                }.value
                guard !Task.isCancelled else { return }
                sourceIcon = icon
            }
    }

    private var accessibilitySummary: String {
        var parts = [previewText, Utilities.formatDate(item.timestamp)]
        if let appName = item.sourceApplication?.applicationName, !appName.isEmpty {
            parts.append("from \(appName)")
        }
        if monitor.currentItemID == item.id {
            parts.append("current clipboard content")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Component Parts

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow

            Divider()
                .padding(.vertical, 2)

            contentPreview

            if let copyError {
                Label(copyError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
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
            Text(Utilities.formatRelativeDate(item.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
                .help(Utilities.formatDate(item.timestamp))

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
            if let nsImage = sourceIcon {
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
                monitor.selectedHistoryItem?.id == item.id
                    ? Color.accentColor.opacity(0.8)
                    : (monitor.currentItemID == item.id
                        ? Color.green.opacity(0.5) : Color.gray.opacity(0.3)),
                lineWidth: monitor.selectedHistoryItem?.id == item.id ? 2 : 1
            )
    }

    var typeIndicators: some View {
        HStack(spacing: 4) {
            if monitor.currentItemID == item.id {
                CurrentClipboardBadge()
                    .accessibilityLabel("Current clipboard content")
            }

            if item.contents.contains(where: { $0.canRenderAsText }) {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                    .accessibilityLabel("Text content")
            }

            if item.contents.contains(where: { $0.canRenderAsImage }) {
                Image(systemName: "photo")
                    .foregroundColor(.green)
                    .accessibilityLabel("Image content")
            }

            let hasURL = item.contents.contains(where: {
                $0.formats.contains { format in
                    format.uti.contains("url")
                }
            })

            if hasURL {
                Image(systemName: "link")
                    .foregroundColor(.purple)
                    .accessibilityLabel("URL content")
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
                        Button("Copy \(content.formats[0].typeName)") {
                            reportCopyResult(
                                monitor.copyFormat(content.formats[0], from: content, in: item)
                            )
                        }
                    } else {
                        Menu(getContentMenuLabel(content)) {
                            ForEach(content.formats) { format in
                                Button("Copy \(format.typeName)") {
                                    reportCopyResult(
                                        monitor.copyFormat(format, from: content, in: item)
                                    )
                                }
                            }
                            Divider()
                            Button("Copy All Formats in Group") {
                                reportCopyResult(monitor.copyContent(content, in: item))
                            }
                        }
                    }
                }

                Divider()

                Button("Copy All Content Types") {
                    reportCopyResult(monitor.copyAllContentTypes(item))
                }
            }
        }
    }

    private func reportCopyResult(_ succeeded: Bool) {
        if succeeded {
            copyError = nil
        } else if monitor.captureIncomplete {
            copyError = "Clipboard capture failed. Copy again before using history."
        } else if monitor.isCapturingHistory {
            copyError = "Wait for clipboard capture before copying."
        } else {
            copyError = "This item could not be written to the clipboard."
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

enum ClipboardHistoryFilter {
    static func matching(_ history: [ClipboardHistoryItem], searchText: String,
                         cache: ClipboardSearchTextCache = .shared) -> [ClipboardHistoryItem] {
        guard !searchText.isEmpty else { return history }
        return history.filter { item in
            item.matchesSearchText(searchText, cache: cache)
        }
    }
}

/// A serial query worker keeps large substring scans out of SwiftUI rendering.
/// Rich imports run on RichSearchIndexer instead, so a stalled import cannot hold this queue.
final class HistoryFilterWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.scottopell.spaperclip.history-filter", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0

    func invalidate() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    private func isStale(_ ticket: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation != ticket
    }

    func results(in history: [ClipboardHistoryItem], query: String,
                 richText: [UUID: String], ticket: Int) async -> [ClipboardHistoryItem] {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = history.filter { item in
                    guard !self.isStale(ticket) else { return false }
                    return item.contents.contains { content in
                        // Never ask the shared cache for rich text here: it can wait on
                        // an AppKit import already in progress on another thread.
                        let text = content.decodesRichSearchText
                            ? richText[content.id] : content.searchableText()
                        return text?.localizedCaseInsensitiveContains(query) == true
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }
}

struct HistoryPlainRestoreState {
    private(set) var pendingID: UUID?
    private(set) var itemID: UUID?
    var isPending: Bool { pendingID != nil }

    mutating func begin(for itemID: UUID) -> UUID {
        let id = UUID()
        pendingID = id
        self.itemID = itemID
        return id
    }

    mutating func cancel() {
        pendingID = nil
        itemID = nil
    }

    func invalidatesRefresh(queryChanged: Bool, liveItemIDs: Set<UUID>) -> Bool {
        guard let itemID else { return false }
        return queryChanged || !liveItemIDs.contains(itemID)
    }

    mutating func finish(_ id: UUID) -> Bool {
        guard pendingID == id else { return false }
        cancel()
        return true
    }
}

@available(macOS 14.0, *)
struct HistoryListView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var internalSearchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchResults: [ClipboardHistoryItem] = []
    @State private var queryIsDebouncing = false
    @State private var isVisible = false
    @State private var searching = false
    @State private var pendingRichText = false
    @State private var queryGeneration = 0
    @State private var lastAppliedQuery: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var plainRestoreTask: Task<Void, Never>?
    @State private var plainRestore = HistoryPlainRestoreState()
    @State private var restoreError: String?
    @State private var richIndex: [UUID: String] = [:]
    @State private var richIndexed: Set<UUID> = []
    @State private var richIndexing: Set<UUID> = []
    @State private var filterWorker = HistoryFilterWorker()
    var showSearchBar: Bool = true
    var externalSearchText: String? = nil  // Optional external search text
    var filteredHistoryOverride: [ClipboardHistoryItem]? = nil
    var onItemCopied: () -> Void = {}
    var accessibilityPrefix: String = "clipboard"

    // Add a timer publisher for debouncing
    private let searchTextPublisher = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    var filteredHistory: [ClipboardHistoryItem] {
        if let filteredHistoryOverride { return filteredHistoryOverride }

        if queryIsDebouncing { return [] }
        return effectiveSearchText.isEmpty ? monitor.history : searchResults
    }

    private var effectiveSearchText: String {
        !showSearchBar ? (externalSearchText ?? debouncedSearchText) : debouncedSearchText
    }

    private func applyQuery(preserveSelection: Bool = false) {
        guard isVisible, filteredHistoryOverride == nil, !queryIsDebouncing else { return }
        let history = monitor.history
        let query = effectiveSearchText
        let queryChanged = !preserveSelection || lastAppliedQuery != query
        lastAppliedQuery = query
        if plainRestore.invalidatesRefresh(queryChanged: queryChanged,
                                           liveItemIDs: Set(history.map(\.id))) {
            plainRestoreTask?.cancel()
            plainRestore.cancel()
        }
        if !plainRestore.isPending { restoreError = nil }
        searchTask?.cancel()
        let ticket = filterWorker.invalidate()
        queryGeneration &+= 1
        let generation = queryGeneration
        let liveIDs = Set(history.flatMap(\.contents).map(\.id))
        richIndex = richIndex.filter { liveIDs.contains($0.key) }
        richIndexed.formIntersection(liveIDs)

        if query.isEmpty {
            searching = false
            pendingRichText = false
            searchResults = []
            if !QuickSearchManager.shared.isQuickSearchVisible,
               !history.contains(where: { $0.id == monitor.selectedHistoryItem?.id }) {
                monitor.selectHistoryItem(history.first)
            }
            return
        }

        // Clear old matches immediately, before the scan can finish. Never let Return
        // restore an item from an earlier query while these results are pending.
        searching = true
        if !preserveSelection {
            searchResults = []
            if !QuickSearchManager.shared.isQuickSearchVisible { monitor.selectHistoryItem(nil) }
        }
        let richContents = history.flatMap(\.contents).filter(\.decodesRichSearchText)
        pendingRichText = richContents.contains { !richIndexed.contains($0.id) }
        if richIndexing.isEmpty,
           let content = richContents.first(where: { !richIndexed.contains($0.id) }) {
            richIndexing.insert(content.id)
            RichSearchIndexer.shared.index(content) { text in
                richIndexing.remove(content.id)
                guard isVisible else { return }
                guard monitor.history.contains(where: {
                    $0.contents.contains(where: { $0.id == content.id })
                }) else {
                    applyQuery(preserveSelection: true)
                    return
                }
                richIndexed.insert(content.id)
                if let text { richIndex[content.id] = text }
                if !queryIsDebouncing { applyQuery(preserveSelection: true) }
            }
        }
        let indexed = richIndex
        searchTask = Task {
            let result = await filterWorker.results(in: history, query: query,
                                                    richText: indexed, ticket: ticket)
            guard !Task.isCancelled, isVisible, generation == queryGeneration else { return }
            searching = false
            searchResults = result
            if !QuickSearchManager.shared.isQuickSearchVisible {
                let selected = monitor.selectedHistoryItem
                if !result.contains(where: { $0.id == selected?.id }) {
                    monitor.selectHistoryItem(result.first)
                }
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
        if selectedItem?.id != item.id {
            plainRestoreTask?.cancel()
            plainRestore.cancel()
            restoreError = nil
        }
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
                        searchText: $internalSearchText,
                        placeholder: "Search clipboard history...",
                        onSearchTextChanged: { newText in
                            searchTask?.cancel()
                            plainRestoreTask?.cancel()
                            plainRestore.cancel()
                            restoreError = nil
                            _ = filterWorker.invalidate()
                            queryGeneration &+= 1
                            queryIsDebouncing = true
                            searching = !newText.isEmpty
                            searchResults = []
                            if !QuickSearchManager.shared.isQuickSearchVisible {
                                monitor.selectHistoryItem(nil)
                            }
                            searchTextPublisher.send(newText)
                        }
                    )
                    .accessibilityIdentifier("\(accessibilityPrefix).search")
                }
                .padding(.bottom, 4)
            }

            if pendingRichText && !searching && !queryIsDebouncing && !filteredHistory.isEmpty {
                Text("Rich text is still indexing. Return chooses a shown result.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if plainRestore.isPending || restoreError != nil {
                Text(restoreError ?? "Preparing plain text…")
                    .font(.caption)
                    .foregroundColor(restoreError == nil ? Color.secondary : Color.orange)
            }

            // Always show the ScrollView container regardless of content
            ScrollView {
                if filteredHistory.isEmpty {
                    VStack {
                        if searching || pendingRichText || queryIsDebouncing {
                            Text(pendingRichText && !queryIsDebouncing
                                 ? "Searching… Rich text is still indexing." : "Searching…")
                                .foregroundColor(.secondary)
                        } else if monitor.history.isEmpty {
                            Text("No clipboard history yet. Copy something!")
                                .accessibilityIdentifier("\(accessibilityPrefix).empty-state")
                                .italic()
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            let displaySearchText =
                                !showSearchBar && externalSearchText != nil
                                ? externalSearchText!
                                : debouncedSearchText
                            Text("No results matching '\(displaySearchText)'")
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
                                .accessibilityIdentifier("\(accessibilityPrefix).history.item")
                                .contentShape(Rectangle())
                                .background(
                                    monitor.selectedHistoryItem?.id == item.id
                                        ? Color.accentColor.opacity(0.2) : Color.clear
                                )
                                .cornerRadius(4)
                                .onTapGesture {
                                    selectItem(item)
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
            .accessibilityIdentifier("\(accessibilityPrefix).history")
            .cornerRadius(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)  // Align to top
        .padding(4)
        .onAppear {
            isVisible = true
            // Setup the debounced search
            cancellable =
                searchTextPublisher
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .sink { value in
                    debouncedSearchText = value
                    queryIsDebouncing = false
                    applyQuery()
                }

            applyQuery()
        }
        .onDisappear {
            isVisible = false
            searchTask?.cancel()
            plainRestoreTask?.cancel()
            plainRestore.cancel()
            _ = filterWorker.invalidate()
        }
        .onChange(of: monitor.selectedHistoryItem?.id) { _, newID in
            if plainRestore.isPending && plainRestore.itemID != newID {
                plainRestoreTask?.cancel()
                plainRestore.cancel()
                restoreError = nil
            }
        }
        .onChange(of: monitor.history) { _, _ in applyQuery(preserveSelection: true) }
        .onChange(of: externalSearchText) { _, _ in applyQuery() }
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
        .onKeyPress(.return) { restoreSelectedItem() }
    }

    private func restoreSelectedItem() -> KeyPress.Result {
        monitor.reconcileCurrentPasteboard()
        guard !monitor.isCapturingHistory, !monitor.captureIncomplete else {
            restoreError = monitor.captureIncomplete
                ? "Clipboard capture failed. Copy again before restoring history."
                : "Wait for clipboard capture before restoring history."
            return .handled
        }
        guard !searching, !queryIsDebouncing,
              let item = selectedItem,
              filteredHistory.contains(where: { $0.id == item.id }) else {
            return .handled
        }

        if NSEvent.modifierFlags.contains(.shift) {
            guard !plainRestore.isPending else { return .handled }
            if let plain = item.contents.first(where: { content in
                content.formats.contains(where: {
                    $0.uti == "public.utf8-plain-text" || $0.uti == "public.plain-text"
                })
            }), plain.data.count < 100_000 {
                if monitor.copyPlainTextOnly(item) { onItemCopied() }
                else { restoreError = "Plain text could not be restored." }
                return .handled
            }
            let query = effectiveSearchText
            let clipboardChangeCount = NSPasteboard.general.changeCount
            let restoreID = plainRestore.begin(for: item.id)
            restoreError = nil
            plainRestoreTask = Task {
                let text = await PlainRestoreWorker.text(from: item)
                guard plainRestore.finish(restoreID) else { return }
                guard !Task.isCancelled, isVisible, query == effectiveSearchText,
                      monitor.selectedHistoryItem?.id == item.id else { return }
                guard let text else {
                    restoreError = item.contents.contains(where: {
                        $0.usesLocalHTMLText && $0.data.count > LocalHTMLText.maximumImportBytes
                    }) ? "HTML is too large to convert. Return restores its original formats."
                        : "Plain-text conversion is unavailable. Return restores original formats."
                    return
                }
                let board = NSPasteboard.general
                guard ClipboardRestorePrecondition.isSafe(to: board,
                    expectedChangeCount: clipboardChangeCount,
                    capturePending: monitor.isCapturingHistory,
                    captureIncomplete: monitor.captureIncomplete) else {
                    monitor.reconcileCurrentPasteboard()
                    restoreError = "Clipboard changed while preparing plain text. Try again."
                    return
                }
                board.clearContents()
                guard board.setString(text, forType: .string) else {
                    restoreError = "Plain text could not be written to the clipboard."
                    return
                }
                monitor.promoteRestoredItem(item)
                onItemCopied()
            }
        } else {
            plainRestoreTask?.cancel()
            plainRestore.cancel()
            if monitor.copyAllContentTypes(item) {
                restoreError = nil
                onItemCopied()
            } else {
                restoreError = "This item could not be written to the clipboard."
            }
        }
        return .handled
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
