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

        XCTAssertFalse(Utilities.copyAllContentTypes(from: item, to: pasteboard))
    }
}
