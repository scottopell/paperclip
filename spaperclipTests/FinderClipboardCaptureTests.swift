import AppKit
import XCTest
@testable import spaperclip

final class FinderClipboardCaptureTests: XCTestCase {
    /// Finder's board-wide list includes aliases absent from its native item.
    /// `fndf` returns nil even while the actual file representations are readable.
    func testFinderAliasWithoutBytesDoesNotDiscardFileAndOtherFormats() throws {
        let copiedFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("copied file \(UUID()).txt")
        try Data("file contents".utf8).write(to: copiedFile)
        defer { try? FileManager.default.removeItem(at: copiedFile) }
        let fileURL = NSPasteboard.PasteboardType.fileURL
        let text = NSPasteboard.PasteboardType.string
        let icon = NSPasteboard.PasteboardType("com.apple.icns")
        let nodeRef = NSPasteboard.PasteboardType("com.apple.finder.noderef")
        let legacyFile = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x6675726C")
        let missingAlias = NSPasteboard.PasteboardType("fndf")
        let payloads: [NSPasteboard.PasteboardType: Data] = [
            fileURL: Data(copiedFile.absoluteString.utf8),
            text: Data("copied file.txt".utf8),
            icon: Data([0x69, 0x63, 0x6e, 0x73, 0, 255]),
            nodeRef: Data([0]),
            legacyFile: Data(copiedFile.absoluteString.utf8)
        ]
        let types = [fileURL, legacyFile, nodeRef, missingAlias, text, icon]
        let contents = try XCTUnwrap(ClipboardMonitor.captureContents(
            availableTypes: types, itemTypes: [fileURL, text, icon],
            readData: { payloads[$0] }
        ))
        let captured = contents.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, content in
            for format in content.formats { result[.init(format.uti)] = content.data }
        }
        XCTAssertEqual(captured, payloads, "Every readable format must retain its exact bytes")
        XCTAssertFalse(contents.flatMap(\.formats).contains { $0.uti == missingAlias.rawValue })

        let restored = NSPasteboard(name: .init(UUID().uuidString))
        defer { restored.releaseGlobally() }
        let historyItem = ClipboardHistoryItem(timestamp: .now, contents: contents, sourceApplication: nil)
        XCTAssertTrue(Utilities.copyAllContentTypes(from: historyItem, to: restored))
        for (type, data) in payloads {
            XCTAssertEqual(restored.data(forType: type), data, type.rawValue)
        }
        XCTAssertEqual(
            (restored.readObjects(forClasses: [NSURL.self]) as? [URL])?.first?.absoluteString,
            copiedFile.absoluteString
        )
    }

    func testUnreadableNativeFileRepresentationStillRejectsCapture() {
        let fileURL = NSPasteboard.PasteboardType.fileURL
        let text = NSPasteboard.PasteboardType.string
        XCTAssertNil(ClipboardMonitor.captureContents(
            availableTypes: [fileURL, text], itemTypes: [fileURL, text],
            readData: { $0 == text ? Data("file.txt".utf8) : nil }
        ))
    }

    func testEmptyAliasIsCapturedRatherThanTreatedAsMissing() throws {
        let fileURL = NSPasteboard.PasteboardType.fileURL
        let marker = NSPasteboard.PasteboardType("com.example.marker")
        let contents = try XCTUnwrap(ClipboardMonitor.captureContents(
            availableTypes: [fileURL, marker], itemTypes: [fileURL],
            readData: { $0 == fileURL ? Data("file:///tmp/file.txt".utf8) : Data() }
        ))
        XCTAssertTrue(contents.contains {
            $0.data.isEmpty && $0.formats.contains { $0.uti == marker.rawValue }
        })
    }

    func testFileURLHasReadableDetailAndHistoryPreviews() {
        let url = "file:///tmp/copied%20file.txt"
        let content = ClipboardContent(data: Data(url.utf8),
            formats: [ClipboardFormat(uti: NSPasteboard.PasteboardType.fileURL.rawValue)],
            description: "File URL")
        XCTAssertTrue(content.canRenderAsText)
        XCTAssertEqual(content.textForDisplay(), url)
        XCTAssertEqual(content.getTextRepresentation(), url)
        XCTAssertEqual(content.getTextChunk(offset: 0, length: 100)?.text, url)
    }

    @MainActor
    func testMonitorCapturesAndRestoresFileURLWithNativePasteboardAliases() async throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        let restored = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally(); restored.releaseGlobally() }
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("copied file \(UUID()).txt")
        try Data("file contents".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        board.clearContents()
        XCTAssertTrue(board.writeObjects([url as NSURL]))
        let originalData = Dictionary(uniqueKeysWithValues: (board.types ?? []).compactMap { type in
            board.data(forType: type).map { (type, $0) }
        })
        monitor.reconcileCurrentPasteboard()
        let captured = expectation(for: NSPredicate { _, _ in !monitor.isCapturingHistory }, evaluatedWith: nil)
        await fulfillment(of: [captured], timeout: 5)
        let item = try XCTUnwrap(monitor.history.first)
        XCTAssertFalse(monitor.captureIncomplete)
        XCTAssertEqual(monitor.currentItemID, item.id)
        XCTAssertTrue(Utilities.copyAllContentTypes(from: item, to: restored))
        for (type, data) in originalData {
            XCTAssertEqual(restored.data(forType: type), data, type.rawValue)
        }
    }
}
