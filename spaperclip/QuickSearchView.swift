import AppKit
import SwiftUI

enum QuickSearchQuery {
    private struct MatchRank: Comparable {
        let matchKind: Int
        let wordStarts: Int
        let span: Int
        let gaps: Int
        let start: Int

        static func < (lhs: MatchRank, rhs: MatchRank) -> Bool {
            if lhs.matchKind != rhs.matchKind { return lhs.matchKind < rhs.matchKind }
            if lhs.wordStarts != rhs.wordStarts { return lhs.wordStarts < rhs.wordStarts }
            if lhs.span != rhs.span { return lhs.span > rhs.span }
            if lhs.gaps != rhs.gaps { return lhs.gaps > rhs.gaps }
            return lhs.start > rhs.start
        }
    }

    static func results(
        in history: [ClipboardHistoryItem], matching query: String,
        indexedRichText: [UUID: String]? = nil,
        shouldCancel: () -> Bool = { false }
    ) -> [ClipboardHistoryItem] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return history }

        var ranked: [(item: ClipboardHistoryItem, rank: MatchRank, recency: Int)] = []
        for (index, item) in history.enumerated() {
            if shouldCancel() { return [] }
            let ranks = item.contents.compactMap { content -> MatchRank? in
                if content.decodesRichSearchText, let indexedRichText {
                    guard let text = indexedRichText[content.id] else { return nil }
                    // A small HTML document can expand into a very large plain-text
                    // value. Bound matching by decoded size, not only source bytes.
                    if content.data.count >= 100_000 || text.utf8.count >= 100_000 {
                        guard text.localizedCaseInsensitiveContains(normalizedQuery) else {
                            return nil
                        }
                        return MatchRank(matchKind: 2, wordStarts: 0,
                                         span: normalizedQuery.count, gaps: 0, start: 0)
                    }
                    return rank(text: text, query: normalizedQuery)
                }
                // Preserve detailed fuzzy ranking for normal clipboard values. Building
                // character arrays for a 1 MiB value on every keystroke would defeat the
                // bounded full-text cache, so large values use a cached contiguous match
                // and retain history recency when their ranks are otherwise equal.
                if content.data.count >= 100_000 {
                    guard ClipboardSearchTextCache.shared.matches(normalizedQuery, in: content)
                    else { return nil }
                    return MatchRank(
                        matchKind: 2,
                        wordStarts: 0,
                        span: normalizedQuery.count,
                        gaps: 0,
                        start: 0
                    )
                }
                guard let text = content.searchableText() else { return nil }
                return rank(text: text, query: normalizedQuery)
            }
            guard let bestRank = ranks.max() else { continue }
            ranked.append((item: item, rank: bestRank, recency: index))
        }
        ranked.sort { lhs, rhs in
            if lhs.rank == rhs.rank { return lhs.recency < rhs.recency }
            return lhs.rank > rhs.rank
        }
        return ranked.map { $0.item }
    }

    static func selection(from results: [ClipboardHistoryItem], preferredID: UUID?,
                          currentItemID: UUID?, query: String) -> ClipboardHistoryItem? {
        if let preferredID, let selected = results.first(where: { $0.id == preferredID }) {
            return selected
        }
        return initialSelection(from: results, currentItemID: currentItemID, query: query)
    }

    static func initialSelection(
        from results: [ClipboardHistoryItem],
        currentItemID: UUID?,
        query: String
    ) -> ClipboardHistoryItem? {
        guard query.isEmpty else { return results.first }
        return results.first(where: { $0.id == currentItemID }) ?? results.first
    }

    private static func rank(text: String, query: String) -> MatchRank? {
        let textCharacters = Array(normalized(text))
        let queryCharacters = Array(query)
        guard !textCharacters.isEmpty, !queryCharacters.isEmpty else { return nil }

        if textCharacters == queryCharacters {
            return MatchRank(
                matchKind: 3,
                wordStarts: wordStartCount(in: textCharacters, positions: textCharacters.indices),
                span: queryCharacters.count,
                gaps: 0,
                start: 0
            )
        }

        if let range = contiguousRange(of: queryCharacters, in: textCharacters) {
            return MatchRank(
                matchKind: 2,
                wordStarts: wordStartCount(in: textCharacters, positions: range),
                span: range.count,
                gaps: 0,
                start: range.lowerBound
            )
        }

        // The old matcher greedily completed the query from every possible start.
        // Keep those same choices for short queries, but reuse each suffix result.
        // Bound exceptionally large text × query products to one greedy pass
        // (without losing matches). Ordinary long queries still keep exact ranks.
        if queryCharacters.count > 64 &&
            textCharacters.count > 4_000_000 / queryCharacters.count {
            var next = 0
            var first = 0
            var last = 0
            var wordStarts = 0
            for index in textCharacters.indices where next < queryCharacters.count {
                guard textCharacters[index] == queryCharacters[next] else { continue }
                if next == 0 { first = index }
                last = index
                if index == 0 || !textCharacters[index - 1].isLetterOrNumber {
                    wordStarts += 1
                }
                next += 1
            }
            guard next == queryCharacters.count else { return nil }
            let span = last - first + 1
            return MatchRank(matchKind: 1, wordStarts: wordStarts,
                             span: span, gaps: span - queryCharacters.count, start: first)
        }

        // At each position, suffix[j] describes the greedy completion of query[j...]
        // starting at the first available character to its right. Updating j in
        // ascending order ensures repeated query characters use the prior suffix.
        var suffix = [(end: Int, wordStarts: Int)?](
            repeating: nil, count: queryCharacters.count
        )
        var best: MatchRank?
        for index in textCharacters.indices.reversed() {
            let isWordStart = index == 0 || !textCharacters[index - 1].isLetterOrNumber
            for j in queryCharacters.indices where textCharacters[index] == queryCharacters[j] {
                if j == queryCharacters.count - 1 {
                    suffix[j] = (index, isWordStart ? 1 : 0)
                } else if let remainder = suffix[j + 1] {
                    suffix[j] = (remainder.end, remainder.wordStarts + (isWordStart ? 1 : 0))
                } else {
                    suffix[j] = nil
                }
            }
            guard textCharacters[index] == queryCharacters[0], let match = suffix[0] else {
                continue
            }
            let span = match.end - index + 1
            let candidate = MatchRank(matchKind: 1, wordStarts: match.wordStarts,
                                      span: span, gaps: span - queryCharacters.count, start: index)
            if best == nil || candidate > best! { best = candidate }
        }
        return best
    }

    private static func contiguousRange(
        of query: [Character], in text: [Character]
    ) -> Range<Int>? {
        guard query.count <= text.count else { return nil }
        // KMP avoids rescanning a long common prefix at every text position.
        var prefix = [Int](repeating: 0, count: query.count)
        var matched = 0
        for index in 1..<query.count {
            while matched > 0 && query[index] != query[matched] {
                matched = prefix[matched - 1]
            }
            if query[index] == query[matched] { matched += 1 }
            prefix[index] = matched
        }
        matched = 0
        for index in text.indices {
            while matched > 0 && text[index] != query[matched] {
                matched = prefix[matched - 1]
            }
            if text[index] == query[matched] { matched += 1 }
            if matched == query.count { return (index + 1 - matched)..<(index + 1) }
        }
        return nil
    }

    private static func wordStartCount<S: Sequence>(
        in text: [Character], positions: S
    ) -> Int where S.Element == Int {
        positions.reduce(into: 0) { count, position in
            if position == 0 || !text[position - 1].isLetterOrNumber {
                count += 1
            }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

private extension Character {
    var isLetterOrNumber: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}

enum QuickSearchResultAccessibility {
    static func label(
        preview: String,
        item: ClipboardHistoryItem,
        isSelected: Bool,
        isCurrent: Bool,
        now: Date = Date()
    ) -> String {
        var parts: [String] = []
        if isSelected { parts.append("Selected") }
        if isCurrent { parts.append("Current clipboard item") }
        parts.append(Utilities.formatRelativeDate(item.timestamp, relativeTo: now))
        if let appName = item.sourceApplication?.applicationName, !appName.isEmpty {
            parts.append("from \(appName)")
        }
        if item.hasImageRepresentation {
            parts.append("Image")
        } else if item.contents.contains(where: { content in
            content.formats.contains(where: { $0.uti.localizedCaseInsensitiveContains("url") })
        }) {
            parts.append("Link")
        } else if item.contents.contains(where: { $0.canRenderAsText }) {
            parts.append("Text")
        } else {
            parts.append("Data")
        }
        parts.append(preview)
        return parts.joined(separator: ", ")
    }
}

private struct QuickSearchResultRow: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    @State private var preview = "Loading…"
    @State private var sourceIcon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(Utilities.formatRelativeDate(item.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(Utilities.formatDate(item.timestamp))

                if let appName = item.sourceApplication?.applicationName, !appName.isEmpty {
                    Text("• \(appName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isCurrent {
                    CurrentClipboardBadge()
                }
            }

            HStack(alignment: .top, spacing: 9) {
                if let icon = sourceIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: item.hasImageRepresentation ? "photo" : "doc.text")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }

                Text(preview)
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.1),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            QuickSearchResultAccessibility.label(
                preview: preview,
                item: item,
                isSelected: isSelected,
                isCurrent: isCurrent
            )
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onTapGesture(perform: onSelect)
        .task(id: item.id) {
            sourceIcon = nil
            guard let bundleID = item.sourceApplication?.bundleIdentifier else { return }
            let icon = await Task.detached(priority: .utility) {
                SourceApplicationIconCache.shared.icon(for: bundleID)
            }.value
            guard !Task.isCancelled else { return }
            sourceIcon = icon
        }
        .task(id: item.id) {
            preview = "Loading…"
            let text = await Task.detached(priority: .userInitiated) {
                for content in item.contents {
                    if let (text, _) = content.getTextChunk(offset: 0, length: 180) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                    }
                }
                return ClipboardHistoryPreview.fallbackText(for: item)
            }.value
            guard !Task.isCancelled else { return }
            preview = text
        }
    }
}

private struct QuickSearchResultsList: View {
    let items: [ClipboardHistoryItem]
    @ObservedObject var monitor: ClipboardMonitor
    let query: String
    let isPending: Bool
    let onUserSelect: (ClipboardHistoryItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if items.isEmpty {
                    ContentUnavailableView(
                        isPending ? "Searching…" : (monitor.history.isEmpty ? "No Clipboard History" : "No Matches"),
                        systemImage: "clipboard",
                        description: Text(
                            isPending ? "Results are still loading."
                                : (monitor.history.isEmpty
                                    ? "Copy something to get started."
                                    : "No results matching ‘\(query)’." )
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            QuickSearchResultRow(
                                item: item,
                                isSelected: monitor.selectedHistoryItem?.id == item.id,
                                isCurrent: monitor.currentItemID == item.id,
                                onSelect: { onUserSelect(item) }
                            )
                            .id(item.id)
                            .accessibilityIdentifier("quick-search.history.item")
                        }
                    }
                    .padding(8)
                }
            }
            .accessibilityIdentifier("quick-search.history")
            .onChange(of: monitor.selectedHistoryItem?.id) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Rich imports have their own serial worker so a stuck system HTML helper cannot
/// hold up plain-text queries or create one blocked thread per keystroke.
final class RichSearchIndexer {
    static let shared = RichSearchIndexer()
    private let queue = DispatchQueue(label: "com.scottopell.spaperclip.rich-search", qos: .userInitiated)
    private let decode: (ClipboardContent) -> String?

    init(decode: @escaping (ClipboardContent) -> String? = { $0.searchableText() }) {
        self.decode = decode
    }

    func index(_ content: ClipboardContent, completion: @escaping (String?) -> Void) {
        queue.async {
            let text = self.decode(content)
            DispatchQueue.main.async { completion(text) }
        }
    }
}

enum QuickSearchWorker {
    private static let queue = DispatchQueue(label: "com.scottopell.spaperclip.query", qos: .userInitiated)
    private static let lock = NSLock()
    private static var generation = 0

    static func invalidate() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    private static func isStale(_ ticket: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation != ticket
    }

    static func results(in history: [ClipboardHistoryItem], query: String,
                        richText: [UUID: String], ticket: Int) async -> [ClipboardHistoryItem] {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = isStale(ticket) ? [] : QuickSearchQuery.results(
                    in: history, matching: query, indexedRichText: richText,
                    shouldCancel: { isStale(ticket) })
                continuation.resume(returning: result)
            }
        }
    }
}

enum ClipboardRestorePrecondition {
    static func isSafe(to pasteboard: NSPasteboard, expectedChangeCount: Int,
                       capturePending: Bool, captureIncomplete: Bool) -> Bool {
        pasteboard.changeCount == expectedChangeCount && !capturePending && !captureIncomplete
    }
}

enum PlainRestoreWorker {
    static let queue = DispatchQueue(label: "com.scottopell.spaperclip.plain-restore", qos: .userInitiated)

    static func text(from item: ClipboardHistoryItem) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Utilities.plainText(from: item)) }
        }
    }
}

struct QuickSearchView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var manager: QuickSearchManager
    @State private var searchText: String = ""
    @State private var filteredHistory: [ClipboardHistoryItem] = []
    @State private var restoreError: String?
    @State private var searching = false
    @State private var pendingRichText = false
    @State private var searchTask: Task<Void, Never>?
    @State private var richIndex: [UUID: String] = [:]
    @State private var richIndexing: Set<UUID> = []
    @State private var richIndexed: Set<UUID> = []
    @State private var restoreTask: Task<Void, Never>?
    @State private var isPreparingPlainText = false
    @State private var restoreGeneration = 0
    @State private var queryGeneration = 0
    @State private var queuedRestore: (generation: Int, plainTextOnly: Bool)?
    @State private var explicitSelectionID: UUID?
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

            HSplitView {
                QuickSearchResultsList(
                    items: filteredHistory,
                    monitor: monitor,
                    query: searchText,
                    isPending: searching || pendingRichText || monitor.isCapturingHistory
                        || monitor.captureIncomplete,
                    onUserSelect: { item in
                        explicitSelectionID = item.id
                        monitor.selectHistoryItem(item)
                    }
                )
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 390)

                ClipboardDetailView(monitor: monitor)
                    .accessibilityIdentifier("quick-search.preview")
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding([.horizontal, .bottom], 16)
            .padding(.top, 10)

            if searching || pendingRichText || monitor.isCapturingHistory || monitor.captureIncomplete {
                Text(monitor.captureIncomplete
                    ? "Clipboard capture failed; previous history is unchanged. Copy again to retry."
                    : (monitor.isCapturingHistory ? "Capturing clipboard…"
                        : (searching ? "Searching…"
                            : "Indexing rich text… Results may be incomplete.")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .accessibilityIdentifier("quick-search.pending")
            }

            if let restoreError {
                Label(restoreError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("quick-search.restore-error")
            }

            HStack(spacing: 18) {
                Label("Paste", systemImage: "return")
                Text("⇧↩ Paste Plain Text")
                Text("↑↓ Navigate")
                Text("esc Close")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Return pastes, Shift Return pastes plain text, arrow keys navigate, Escape closes"
            )
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
        )
        .frame(minWidth: 820, minHeight: 500)
        .onChange(of: monitor.history) { _, _ in
            applyQuery(searchText, preserveSelection: true)
        }
        .onChange(of: manager.isQuickSearchVisible) { _, visible in
            if !visible {
                queryGeneration &+= 1
                queuedRestore = nil
                explicitSelectionID = nil
                _ = QuickSearchWorker.invalidate()
                searchTask?.cancel()
                restoreTask?.cancel()
                restoreGeneration &+= 1
                isPreparingPlainText = false
            }
        }
        .task(id: manager.presentationID) {
            explicitSelectionID = nil
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

    private func applyQuery(_ query: String, preserveSelection: Bool = false) {
        if !preserveSelection { explicitSelectionID = nil }
        restoreError = nil
        queuedRestore = nil
        restoreTask?.cancel()
        restoreGeneration &+= 1
        isPreparingPlainText = false
        searchTask?.cancel()
        let ticket = QuickSearchWorker.invalidate()
        queryGeneration &+= 1
        let generation = queryGeneration
        let history = monitor.history
        let liveIDs = Set(history.flatMap(\.contents).map(\.id))
        richIndex = richIndex.filter { liveIDs.contains($0.key) }
        richIndexed.formIntersection(liveIDs)
        if query.isEmpty {
            searching = false
            pendingRichText = false
            publishResults(history, query: query)
            return
        }

        // Rich import may wait indefinitely on a system helper. One serial worker
        // indexes each representation once; ordinary text queries never wait for it.
        let richContents = history.flatMap(\.contents).filter(\.decodesRichSearchText)
        pendingRichText = richContents.contains { !richIndexed.contains($0.id) }
        if richIndexing.isEmpty,
           let content = richContents.first(where: { !richIndexed.contains($0.id) }) {
            richIndexing.insert(content.id)
            RichSearchIndexer.shared.index(content) { text in
                richIndexing.remove(content.id)
                guard monitor.history.contains(where: {
                    $0.contents.contains(where: { $0.id == content.id })
                }) else {
                    // The removed item no longer holds the only indexing slot.
                    // Start work on any rich item captured while it was blocked.
                    if manager.isQuickSearchVisible {
                        applyQuery(searchText, preserveSelection: true)
                    }
                    return
                }
                richIndexed.insert(content.id)
                if let text { richIndex[content.id] = text }
                if manager.isQuickSearchVisible { applyQuery(searchText, preserveSelection: true) }
            }
        }
        searching = true
        if !preserveSelection {
            filteredHistory = []
            monitor.selectHistoryItem(nil)
        }
        let indexed = richIndex
        searchTask = Task {
            let result = await QuickSearchWorker.results(in: history, query: query,
                richText: indexed, ticket: ticket)
            guard !Task.isCancelled, generation == queryGeneration,
                  manager.isQuickSearchVisible else { return }
            searching = false
            publishResults(result, query: query)
            if let queued = queuedRestore, queued.generation == generation {
                queuedRestore = nil
                _ = restoreSelection(plainTextOnly: queued.plainTextOnly)
            }
        }
    }

    private func publishResults(_ result: [ClipboardHistoryItem], query: String) {
        filteredHistory = result
        monitor.selectHistoryItem(QuickSearchQuery.selection(
            from: result, preferredID: explicitSelectionID,
            currentItemID: monitor.currentItemID, query: query))
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !filteredHistory.isEmpty else { return .handled }
        restoreError = nil

        let currentIndex = monitor.selectedHistoryItem.flatMap { selected in
            filteredHistory.firstIndex(where: { $0.id == selected.id })
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), filteredHistory.count - 1)
        explicitSelectionID = filteredHistory[nextIndex].id
        monitor.selectHistoryItem(filteredHistory[nextIndex])
        return .handled
    }

    private func restoreSelection(plainTextOnly override: Bool? = nil) -> KeyPress.Result {
        // Recheck the change count even if the polling timer has not fired yet.
        monitor.reconcileCurrentPasteboard()
        guard !monitor.isCapturingHistory, !monitor.captureIncomplete else {
            queuedRestore = nil
            restoreError = monitor.captureIncomplete
                ? "Clipboard capture failed. Copy again before restoring history."
                : "Wait for clipboard capture before pasting."
            return .handled
        }
        let plainTextOnly = override ?? NSEvent.modifierFlags.contains(.shift)
        if searching {
            if pendingRichText {
                restoreError = "Rich text is still indexing. Press Return again to choose a shown result."
            } else {
                queuedRestore = (queryGeneration, plainTextOnly)
            }
            return .handled
        }
        guard let selected = monitor.selectedHistoryItem,
            filteredHistory.contains(where: { $0.id == selected.id })
        else {
            return .handled
        }

        if plainTextOnly {
            if let plain = selected.contents.first(where: { content in
                content.formats.contains(where: {
                    $0.uti == "public.utf8-plain-text" || $0.uti == "public.plain-text"
                })
            }), plain.data.count < 100_000 {
                guard monitor.copyPlainTextOnly(selected) else {
                    restoreError = "This item has no plain-text representation."
                    return .handled
                }
                restoreError = manager.pasteIntoInvokingApplication()
                return .handled
            }
            guard !isPreparingPlainText else { return .handled }
            let session = manager.presentationID
            let query = searchText
            let clipboardChangeCount = NSPasteboard.general.changeCount
            restoreGeneration &+= 1
            let generation = restoreGeneration
            isPreparingPlainText = true
            restoreError = "Preparing plain text…"
            restoreTask = Task {
                let text = await PlainRestoreWorker.text(from: selected)
                guard generation == restoreGeneration else { return }
                isPreparingPlainText = false
                guard !Task.isCancelled, manager.isQuickSearchVisible,
                      manager.presentationID == session, searchText == query,
                      monitor.selectedHistoryItem?.id == selected.id else { return }
                guard let text else {
                    restoreError = "This item has no plain-text representation."
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
                monitor.promoteRestoredItem(selected)
                restoreError = manager.pasteIntoInvokingApplication()
            }
            return .handled
        }
        let copied = plainTextOnly
            ? monitor.copyPlainTextOnly(selected)
            : monitor.copyAllContentTypes(selected)
        guard copied else {
            restoreError = plainTextOnly
                ? "This item has no plain-text representation."
                : "This item could not be written to the clipboard."
            return .handled
        }

        restoreError = manager.pasteIntoInvokingApplication()
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
