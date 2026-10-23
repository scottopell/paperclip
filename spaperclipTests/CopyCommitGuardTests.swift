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

    func testFailureStagesDoNotExposeClipboardData() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let empty = ClipboardHistoryItem(timestamp: .now, contents: [], sourceApplication: nil)
        var failure: ClipboardWriteFailure?
        XCTAssertFalse(Utilities.copyAllContentTypes(from: empty, to: board,
            onFailure: { failure = $0 }))
        XCTAssertEqual(failure, .noFormats)

        let (item, _, _) = makeItem()
        let oldCount = board.changeCount
        board.clearContents()
        XCTAssertTrue(board.setString("unchanged", forType: .string))
        failure = nil
        XCTAssertFalse(Utilities.copyAllContentTypes(from: item, to: board,
            expectedChangeCount: oldCount, onFailure: { failure = $0 }))
        XCTAssertEqual(failure, .clipboardChanged)
        XCTAssertEqual(board.string(forType: .string), "unchanged")
    }

    func testAllTypesRestorePreservesLegacyPasteboardNames() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let html = Data("<p>disposable</p>".utf8)
        let plain = Data("disposable".utf8)
        let representations: [(String, Data)] = [
            ("public.html", html),
            ("Apple HTML pasteboard type", html),
            ("public.utf8-plain-text", plain),
            ("NSStringPboardType", plain),
            ("org.chromium.internal.source-rfh-token", Data([1, 2, 3])),
            ("org.chromium.source-url", Data("https://example.invalid".utf8))
        ]
        let item = ClipboardHistoryItem(timestamp: .now, contents: representations.map { type, data in
            ClipboardContent(data: data, formats: [ClipboardFormat(uti: type)], description: type)
        }, sourceApplication: nil)
        XCTAssertTrue(Utilities.copyAllContentTypes(from: item, to: board))
        for (type, data) in representations {
            XCTAssertEqual(board.data(forType: .init(type)), data, "Format must survive: \(type)")
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
        XCTAssertEqual(monitor.lastRestoreFailure, .conflictingFormats)
        XCTAssertNil(monitor.currentItemID)
        XCTAssertTrue(monitor.history.isEmpty)
    }
}
