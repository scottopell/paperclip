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
        in history: [ClipboardHistoryItem], matching query: String
    ) -> [ClipboardHistoryItem] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return history }

        var ranked: [(item: ClipboardHistoryItem, rank: MatchRank, recency: Int)] = []
        for (index, item) in history.enumerated() {
            let ranks = item.contents.compactMap { content -> MatchRank? in
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
            let positions = range.map { $0 }
            return MatchRank(
                matchKind: 2,
                wordStarts: wordStartCount(in: textCharacters, positions: positions),
                span: range.count,
                gaps: 0,
                start: range.lowerBound
            )
        }

        var best: MatchRank?
        for start in textCharacters.indices where textCharacters[start] == queryCharacters[0] {
            var positions = [start]
            var textIndex = start + 1
            var queryIndex = 1

            while textIndex < textCharacters.count && queryIndex < queryCharacters.count {
                if textCharacters[textIndex] == queryCharacters[queryIndex] {
                    positions.append(textIndex)
                    queryIndex += 1
                }
                textIndex += 1
            }

            guard queryIndex == queryCharacters.count, let end = positions.last else { continue }
            let span = end - start + 1
            let candidate = MatchRank(
                matchKind: 1,
                wordStarts: wordStartCount(in: textCharacters, positions: positions),
                span: span,
                gaps: span - queryCharacters.count,
                start: start
            )
            if best == nil || candidate > best! { best = candidate }
        }
        return best
    }

    private static func contiguousRange(
        of query: [Character], in text: [Character]
    ) -> Range<Int>? {
        guard query.count <= text.count else { return nil }
        for start in 0...(text.count - query.count) {
            let end = start + query.count
            if Array(text[start..<end]) == query { return start..<end }
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
                if let icon = item.sourceApplication?.applicationIcon {
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
            preview = await Task.detached(priority: .userInitiated) {
                for content in item.contents {
                    if let (text, _) = content.getTextChunk(offset: 0, length: 180) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                    }
                }
                return ClipboardHistoryPreview.fallbackText(for: item)
            }.value
        }
    }
}

private struct QuickSearchResultsList: View {
    let items: [ClipboardHistoryItem]
    @ObservedObject var monitor: ClipboardMonitor
    let query: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if items.isEmpty {
                    ContentUnavailableView(
                        monitor.history.isEmpty ? "No Clipboard History" : "No Matches",
                        systemImage: "clipboard",
                        description: Text(
                            monitor.history.isEmpty
                                ? "Copy something to get started."
                                : "No results matching ‘\(query)’."
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
                                onSelect: { monitor.selectHistoryItem(item) }
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

struct QuickSearchView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var manager: QuickSearchManager
    @State private var searchText: String = ""
    @State private var filteredHistory: [ClipboardHistoryItem] = []
    @State private var restoreError: String?
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
                    query: searchText
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
        restoreError = nil
        filteredHistory = QuickSearchQuery.results(
            in: monitor.history, matching: query
        )
        monitor.selectHistoryItem(
            QuickSearchQuery.initialSelection(
                from: filteredHistory,
                currentItemID: monitor.currentItemID,
                query: query
            )
        )
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !filteredHistory.isEmpty else { return .handled }
        restoreError = nil

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

        let plainTextOnly = NSEvent.modifierFlags.contains(.shift)
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
