import AppKit
import XCTest
@testable import spaperclip

/// Named pasteboards keep these commit-boundary tests off the user's clipboard.
@MainActor
final class CopyCommitGuardTests: XCTestCase {
    private let textType = NSPasteboard.PasteboardType("public.utf8-plain-text")
    private let binaryType = NSPasteboard.PasteboardType("com.example.exact-bytes")

    private func makeItem() -> (ClipboardHistoryItem, ClipboardContent, ClipboardFormat) {
        let format = ClipboardFormat(uti: textType.rawValue)
        let content = ClipboardContent(data: Data("restored".utf8), formats: [format],
                                       description: "restored")
        let binary = ClipboardContent(data: Data([0, 255, 37, 0]),
                                      formats: [ClipboardFormat(uti: binaryType.rawValue)],
                                      description: "binary")
        return (ClipboardHistoryItem(timestamp: Date(), contents: [content, binary],
                                     sourceApplication: nil), content, format)
    }

    func testEveryCopyChecksExpectedCountBeforeReplacingExternalBytes() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let (item, content, format) = makeItem()
        let oldCount = board.changeCount
        let external = Data([0, 255, 42, 10])
        board.clearContents()
        XCTAssertTrue(board.setData(external, forType: binaryType))
        let currentCount = board.changeCount
        XCTAssertNotEqual(oldCount, currentCount)

        let attempts: [() -> Bool] = [
            { Utilities.copy(format, from: content, to: board, expectedChangeCount: oldCount) },
            { Utilities.copyToClipboard(content, to: board, expectedChangeCount: oldCount) },
            { Utilities.copyAllContentTypes(from: item, to: board,
                                            expectedChangeCount: oldCount) },
            { Utilities.copyPlainText(from: item, to: board,
                                      expectedChangeCount: oldCount) }
        ]
        for attempt in attempts {
            XCTAssertFalse(attempt())
            XCTAssertEqual(board.changeCount, currentCount, "failed commit must not clear pasteboard")
            XCTAssertEqual(board.data(forType: binaryType), external)
            XCTAssertNil(board.data(forType: textType))
        }
    }

    func testSuccessfulCopyRetainsExactBinaryRepresentations() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let (item, _, _) = makeItem()
        XCTAssertTrue(Utilities.copyAllContentTypes(from: item, to: board,
                                                     expectedChangeCount: board.changeCount))
        XCTAssertEqual(board.data(forType: binaryType), Data([0, 255, 37, 0]))
        XCTAssertEqual(board.data(forType: textType), Data("restored".utf8))
    }

    func testMonitorFailureDoesNotPromoteItemOrReportSuccessfulCopy() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        let (item, _, _) = makeItem()
        let missing = ClipboardContent(data: Data("missing".utf8), formats: [],
                                       description: "missing")
        XCTAssertFalse(monitor.copyContent(missing, in: item))
        XCTAssertNil(monitor.currentItemID)
        XCTAssertTrue(monitor.history.isEmpty)
        XCTAssertFalse(monitor.isCapturingHistory)

        // A failed staged write must not promote its source item either.
        let conflicting = ClipboardHistoryItem(timestamp: Date(), contents: [
            ClipboardContent(data: Data("one".utf8),
                             formats: [ClipboardFormat(uti: textType.rawValue)], description: "one"),
            ClipboardContent(data: Data("two".utf8),
                             formats: [ClipboardFormat(uti: textType.rawValue)], description: "two")
        ], sourceApplication: nil)
        XCTAssertFalse(monitor.copyAllContentTypes(conflicting))
        XCTAssertNil(monitor.currentItemID)
        XCTAssertTrue(monitor.history.isEmpty)
    }
}
