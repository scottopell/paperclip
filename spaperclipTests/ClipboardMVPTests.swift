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

        XCTAssertFalse(Utilities.copyAllContentTypes(from: item, to: pasteboard))
    }
}
