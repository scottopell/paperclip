import AppKit
import XCTest

@testable import spaperclip

final class ClipboardMVPTests: XCTestCase {
    private func textItem(_ text: String) -> ClipboardHistoryItem {
        let content = ClipboardContent(
            data: Data(text.utf8),
            formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
            description: text
        )
        return ClipboardHistoryItem(
            timestamp: Date(),
            contents: [content],
            sourceApplication: nil
        )
    }

    func testHistoryFilterIsCaseInsensitiveAndPreservesOrder() {
        let first = textItem("Alpha result")
        let second = textItem("unrelated")
        let third = textItem("another ALPHA result")

        let matches = ClipboardHistoryFilter.matching(
            [first, second, third],
            searchText: "alpha"
        )

        XCTAssertEqual(matches.map(\.id), [first.id, third.id])
    }

    func testHistoryFilterReturnsAllItemsForEmptySearch() {
        let history = [textItem("first"), textItem("second")]

        XCTAssertEqual(
            ClipboardHistoryFilter.matching(history, searchText: "").map(\.id),
            history.map(\.id)
        )
    }

    func testQuickSearchFuzzyRankingPrefersExactThenContiguousThenGapped() {
        let fuzzy = textItem("Quick Search Result")
        let contiguous = textItem("prefix qsr suffix")
        let exact = textItem("QSR")
        let unrelated = textItem("clipboard history")

        let matches = QuickSearchQuery.results(
            in: [fuzzy, unrelated, contiguous, exact],
            matching: "qsr"
        )

        XCTAssertEqual(matches.map(\.id), [exact.id, contiguous.id, fuzzy.id])
    }

    func testQuickSearchFuzzyMatchingIsCaseAndDiacriticInsensitive() {
        let cafe = textItem("CAFÉ receipt")

        XCTAssertEqual(
            QuickSearchQuery.results(in: [cafe], matching: "cafe").map(\.id),
            [cafe.id]
        )
    }

    func testQuickSearchFuzzyRankingPrefersWordStarts() {
        let midWord = textItem("acmeb record")
        let wordStarts = textItem("alpha beta record")

        XCTAssertEqual(
            QuickSearchQuery.results(
                in: [midWord, wordStarts], matching: "abr"
            ).map(\.id),
            [wordStarts.id, midWord.id]
        )
    }

    func testQuickSearchEqualRanksKeepRecencyOrder() {
        let newer = textItem("quick search row")
        let older = textItem("quick search row")

        XCTAssertEqual(
            QuickSearchQuery.results(in: [newer, older], matching: "qsr").map(\.id),
            [newer.id, older.id]
        )
    }

    func testQuickSearchInitialSelectionUsesCurrentItemID() {
        let first = textItem("first")
        let current = textItem("current")
        let results = [first, current]

        XCTAssertEqual(
            QuickSearchQuery.initialSelection(
                from: results, currentItemID: current.id, query: "")?.id,
            current.id
        )
        XCTAssertEqual(
            QuickSearchQuery.initialSelection(
                from: results, currentItemID: current.id, query: "cur")?.id,
            first.id
        )
        XCTAssertEqual(
            QuickSearchQuery.initialSelection(
                from: results, currentItemID: nil, query: "")?.id,
            first.id
        )
        XCTAssertEqual(
            QuickSearchQuery.initialSelection(
                from: results, currentItemID: UUID(), query: "")?.id,
            first.id
        )
    }

    func testPromotingHistoryItemPreservesIdentityAndMovesItFirst() {
        let first = textItem("first")
        let selected = textItem("selected")
        let promotionDate = Date(timeIntervalSince1970: 1234)

        let result = ClipboardHistoryState.promoting(
            selected, in: [first, selected], at: promotionDate)

        XCTAssertEqual(result.item.id, selected.id)
        XCTAssertEqual(result.item.timestamp, promotionDate)
        XCTAssertEqual(result.history.map(\.id), [selected.id, first.id])
        XCTAssertEqual(result.history.count, 2)
    }

    func testRichHistoryItemContainsItsPlainTextRestore() {
        let textData = Data("restored text".utf8)
        let richItem = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [
                ClipboardContent(
                    data: textData,
                    formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                    description: "restored text"
                ),
                ClipboardContent(
                    data: Data("{\\rtf1 restored text}".utf8),
                    formats: [ClipboardFormat(uti: "public.rtf")],
                    description: "rich text"
                ),
            ],
            sourceApplication: nil
        )
        let plainTextCapture = [
            ClipboardContent(
                data: textData,
                formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                description: "restored text"
            )
        ]

        XCTAssertTrue(richItem.containsRepresentations(from: plainTextCapture))
    }

    @MainActor
    func testLayoutAwareShortcutFindsPrintableCharacterKeyCode() {
        guard let keyCode = LayoutAwareShortcutManager.keyCode(for: "s") else {
            return XCTFail("Expected the active keyboard layout to contain s")
        }

        XCTAssertEqual(
            LayoutAwareShortcutManager.character(forKeyCode: keyCode).map {
                String($0).lowercased()
            },
            "s"
        )
    }

    func testLegacyImagePasteboardTypesHaveCompactLabels() {
        XCTAssertEqual(ClipboardFormat(uti: "NeXT TIFF v4.0 pasteboard type").shortTypeName, "TIFF")
        XCTAssertEqual(ClipboardFormat(uti: "Apple PNG pasteboard type").shortTypeName, "PNG")
    }

    func testImageHistoryPreviewIsLabeledAsImage() {
        let imageContent = ClipboardContent(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            formats: [ClipboardFormat(uti: "public.png")],
            description: "PNG image"
        )
        let item = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [imageContent],
            sourceApplication: nil
        )

        XCTAssertEqual(ClipboardHistoryPreview.fallbackText(for: item), "(Image)")
    }

    func testUnknownHistoryPreviewRemainsUnsupported() {
        let content = ClipboardContent(
            data: Data([0x00]),
            formats: [ClipboardFormat(uti: "com.example.unknown")],
            description: "Unknown"
        )
        let item = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [content],
            sourceApplication: nil
        )

        XCTAssertEqual(ClipboardHistoryPreview.fallbackText(for: item), "(Unsupported format)")
    }

    func testCopyAllContentTypesWritesToPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("spaperclip-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let item = textItem("restored clipboard value")

        XCTAssertTrue(Utilities.copyAllContentTypes(from: item, to: pasteboard))
        XCTAssertEqual(
            pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")),
            "restored clipboard value"
        )
    }

    func testCopyAllContentTypesRejectsEmptyItem() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("spaperclip-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let item = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [],
            sourceApplication: nil
        )

        XCTAssertTrue(pasteboard.setString("keep me", forType: .string))
        XCTAssertFalse(Utilities.copyAllContentTypes(from: item, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }

    func testPlainTextRestoreRejectsImageWithoutClearingPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("spaperclip-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.setString("keep me", forType: .string))
        let imageItem = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [
                ClipboardContent(
                    data: Data([0x89, 0x50, 0x4E, 0x47]),
                    formats: [ClipboardFormat(uti: "public.png")],
                    description: "PNG image"
                )
            ],
            sourceApplication: nil
        )

        XCTAssertFalse(Utilities.copyPlainText(from: imageItem, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }
}
