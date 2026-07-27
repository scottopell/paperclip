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
            guard let text = item.textRepresentation else { continue }
            guard let matchRank = rank(text: text, query: normalizedQuery) else { continue }
            ranked.append((item: item, rank: matchRank, recency: index))
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
