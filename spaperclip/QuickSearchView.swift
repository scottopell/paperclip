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
                        guard text.range(of: normalizedQuery,
                            options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
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
            for content in item.contents {
                if let text = await ClipboardPreviewText.chunk(for: content, length: 180) {
                    guard !Task.isCancelled else { return }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        preview = trimmed
                        return
                    }
                }
            }
            guard !Task.isCancelled else { return }
            preview = ClipboardHistoryPreview.fallbackText(for: item)
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

/// Search owns a serial lane; speculative previews and full-size detail loads
/// cannot get ahead of indexing or a plain-text restore on that lane.
final class RichSearchIndexer {
    static let shared = RichSearchIndexer()
    private let searchQueue = DispatchQueue(label: "com.scottopell.spaperclip.rich-search", qos: .userInitiated)
    private let previewQueue = DispatchQueue(label: "com.scottopell.spaperclip.rich-preview", qos: .utility)
    private let detailQueue = DispatchQueue(label: "com.scottopell.spaperclip.rich-detail", qos: .userInitiated)
    private let lock = NSLock()
    private let cache = NSCache<NSUUID, NSString>()
    private var indexing: [UUID: [(String?) -> Void]] = [:]
    private var detailing: [UUID: [(String?) -> Void]] = [:]
    private var previewing: [UUID: [(String?) -> Void]] = [:]
    private let decode: ((ClipboardContent) -> String?)?

    // The injection is for blocked-parser tests; production parses HTML locally.
    init(decode: ((ClipboardContent) -> String?)? = nil) {
        self.decode = decode
        cache.totalCostLimit = 16_000_000
    }

    /// Search is limited to 500 KB. Explicit full-size reads use another lane.
    func index(_ content: ClipboardContent, allowLarge: Bool = false,
               completion: @escaping (String?) -> Void) {
        if content.usesLocalHTMLText && content.data.count > LocalHTMLText.maximumImportBytes {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        if !allowLarge && content.usesLocalHTMLText && content.data.count >= 500_000 {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        lock.lock()
        if let cached = cache.object(forKey: content.id as NSUUID) {
            lock.unlock()
            DispatchQueue.main.async { completion(cached as String) }
            return
        }
        if allowLarge, content.data.count < 500_000, indexing[content.id] != nil {
            indexing[content.id]!.append(completion)
            lock.unlock()
            return
        }
        if allowLarge, detailing[content.id] != nil {
            detailing[content.id]!.append(completion)
            lock.unlock()
            return
        }
        if !allowLarge, indexing[content.id] != nil {
            indexing[content.id]!.append(completion)
            lock.unlock()
            return
        }
        if allowLarge {
            detailing[content.id] = [completion]
        } else {
            indexing[content.id] = [completion]
        }
        lock.unlock()

        let work = {
            let text = self.decoded(content)
            self.lock.lock()
            if let text, text.utf8.count <= self.cache.totalCostLimit {
                self.cache.setObject(text as NSString, forKey: content.id as NSUUID,
                                     cost: text.utf8.count)
            }
            let completions: [(String?) -> Void]
            if allowLarge {
                completions = self.detailing.removeValue(forKey: content.id) ?? []
            } else {
                completions = self.indexing.removeValue(forKey: content.id) ?? []
            }
            self.lock.unlock()
            DispatchQueue.main.async { completions.forEach { $0(text) } }
        }
        if allowLarge {
            detailQueue.async(execute: work)
        } else {
            searchQueue.async(execute: work)
        }
    }

    /// A preview can join an active search, but search never joins a preview.
    func preview(_ content: ClipboardContent, completion: @escaping (String?) -> Void) {
        if content.usesLocalHTMLText && content.data.count > LocalHTMLText.maximumImportBytes {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        lock.lock()
        if let cached = cache.object(forKey: content.id as NSUUID) {
            lock.unlock()
            DispatchQueue.main.async { completion(cached as String) }
            return
        }
        if content.data.count < 500_000, indexing[content.id] != nil {
            indexing[content.id]!.append(completion)
            lock.unlock()
            return
        }
        if detailing[content.id] != nil {
            detailing[content.id]!.append(completion)
            lock.unlock()
            return
        }
        if previewing[content.id] != nil {
            previewing[content.id]!.append(completion)
            lock.unlock()
            return
        }
        previewing[content.id] = [completion]
        lock.unlock()
        previewQueue.async {
            let text = self.decoded(content)
            self.lock.lock()
            if let text, text.utf8.count <= self.cache.totalCostLimit {
                self.cache.setObject(text as NSString, forKey: content.id as NSUUID,
                                     cost: text.utf8.count)
            }
            let completions = self.previewing.removeValue(forKey: content.id) ?? []
            self.lock.unlock()
            DispatchQueue.main.async { completions.forEach { $0(text) } }
        }
    }

    private func decoded(_ content: ClipboardContent) -> String? {
        if let decode { return decode(content) }
        if content.usesLocalHTMLText { return LocalHTMLText.decode(content.data) }
        return content.searchableText()
    }
}

enum ClipboardPreviewText {
    static func chunk(for content: ClipboardContent, length: Int) async -> String? {
        if content.usesLocalHTMLText {
            let text: String? = await withCheckedContinuation { continuation in
                RichSearchIndexer.shared.preview(content) { continuation.resume(returning: $0) }
            }
            return text.map { String($0.prefix(length)) }
        }
        return await Task.detached(priority: .userInitiated) {
            content.getTextChunk(offset: 0, length: length)?.text
        }.value
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
        // An explicit plain-text representation takes priority even if HTML was
        // captured first. Never route HTML through the synchronous importer.
        if let plain = item.contents.first(where: { content in
            content.formats.contains(where: {
                $0.uti == "public.utf8-plain-text" || $0.uti == "public.plain-text"
            })
        }), let text = await text(from: plain) { return text }
        for content in item.contents {
            if let text = await text(from: content) { return text }
        }
        return nil
    }

    private static func text(from content: ClipboardContent) async -> String? {
        if content.usesLocalHTMLText {
            if content.data.count >= 500_000 {
                // Explicit conversion keeps the whole item, independently of
                // the bounded search index and speculative detail previews.
                return await withCheckedContinuation { continuation in
                    queue.async {
                        continuation.resume(returning: LocalHTMLText.decode(content.data))
                    }
                }
            }
            return await withCheckedContinuation { continuation in
                RichSearchIndexer.shared.index(content) { text in
                    continuation.resume(returning: text)
                }
            }
        }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: content.searchableText()) }
        }
    }
}

enum QuickSearchPlainRestoreSelection {
    static func invalidates(activeItemID: UUID?, selectedItemID: UUID?) -> Bool {
        activeItemID != nil && activeItemID != selectedItemID
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
    @State private var preparingPlainTextItemID: UUID?
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
                        queuedRestore = nil
                        selectionChanged(to: item.id)
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
        .onChange(of: monitor.selectedHistoryItem?.id) { oldID, selectedID in
            guard oldID != selectedID else { return }
            guard selectedID == monitor.selectedHistoryItem?.id else { return }
            selectionChanged(to: selectedID)
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
                preparingPlainTextItemID = nil
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
        preparingPlainTextItemID = nil
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

    private func selectionChanged(to selectedID: UUID?) {
        guard QuickSearchPlainRestoreSelection.invalidates(
            activeItemID: preparingPlainTextItemID, selectedItemID: selectedID
        ) else {
            if !isPreparingPlainText { restoreError = nil }
            return
        }
        restoreTask?.cancel()
        restoreTask = nil
        restoreGeneration &+= 1
        preparingPlainTextItemID = nil
        isPreparingPlainText = false
        restoreError = nil
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !filteredHistory.isEmpty else { return .handled }
        queuedRestore = nil

        let currentIndex = monitor.selectedHistoryItem.flatMap { selected in
            filteredHistory.firstIndex(where: { $0.id == selected.id })
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), filteredHistory.count - 1)
        let next = filteredHistory[nextIndex]
        if monitor.selectedHistoryItem?.id != next.id {
            selectionChanged(to: next.id)
        } else {
            restoreError = nil
        }
        explicitSelectionID = next.id
        monitor.selectHistoryItem(next)
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
            preparingPlainTextItemID = selected.id
            restoreTask = Task {
                let text = await PlainRestoreWorker.text(from: selected)
                guard generation == restoreGeneration else { return }
                isPreparingPlainText = false
                preparingPlainTextItemID = nil
                guard !Task.isCancelled, manager.isQuickSearchVisible,
                      manager.presentationID == session, searchText == query,
                      monitor.selectedHistoryItem?.id == selected.id else { return }
                guard let text else {
                    restoreError = selected.contents.contains(where: {
                        $0.usesLocalHTMLText && $0.data.count > LocalHTMLText.maximumImportBytes
                    }) ? "HTML is too large to convert. Return restores its original formats."
                        : "This item has no plain-text representation."
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
