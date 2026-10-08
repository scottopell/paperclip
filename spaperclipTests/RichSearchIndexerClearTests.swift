import AppKit
import XCTest

@testable import spaperclip

final class RichSearchIndexerClearTests: XCTestCase {
    @MainActor
    func testClearDropsDecodedTextEvenWithEmptyHistory() async {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        let content = html("cached")
        let first = expectation(description: "initial decode")
        RichSearchIndexer.shared.index(content) { text in
            XCTAssertEqual(text, "cached")
            first.fulfill()
        }
        await fulfillment(of: [first], timeout: 3)

        let invalidated = expectation(description: "cached callback invalidated on empty clear")
        RichSearchIndexer.shared.index(content) { text in
            XCTAssertNil(text)
            invalidated.fulfill()
        }
        monitor.clearHistory()
        await fulfillment(of: [invalidated], timeout: 3)
        // A custom decoder makes eviction observable instead of comparing identical text.
        let decodes = DispatchSemaphore(value: 0)
        let indexer = RichSearchIndexer { _ in decodes.signal(); return "decoded" }
        let a = expectation(description: "first custom decode")
        indexer.preview(content) { _ in a.fulfill() }
        await fulfillment(of: [a], timeout: 3)
        indexer.removeAll()
        let b = expectation(description: "second custom decode")
        indexer.preview(content) { _ in b.fulfill() }
        await fulfillment(of: [b], timeout: 3)
        XCTAssertEqual(decodes.wait(timeout: .now()), .success)
        XCTAssertEqual(decodes.wait(timeout: .now()), .success)
        XCTAssertEqual(decodes.wait(timeout: .now()), .timedOut)
    }

    @MainActor
    func testClearInvalidatesAllLanesAndOldWorkCannotReplaceNewRequests() async {
        let contents = [html("search"), html("detail"), html("preview")]
        let started = expectation(description: "all lanes decoding")
        started.expectedFulfillmentCount = 3
        let invalidated = expectation(description: "all pending requests completed with nil")
        invalidated.expectedFulfillmentCount = 3
        let fresh = expectation(description: "fresh requests completed")
        fresh.expectedFulfillmentCount = 3
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var calls: [UUID: Int] = [:]
        let indexer = RichSearchIndexer { content in
            lock.lock()
            calls[content.id, default: 0] += 1
            let count = calls[content.id]!
            lock.unlock()
            if count == 1 {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return "stale"
            }
            return "fresh"
        }
        indexer.index(contents[0]) { text in XCTAssertNil(text); invalidated.fulfill() }
        indexer.index(contents[1], allowLarge: true) { text in
            XCTAssertNil(text); invalidated.fulfill()
        }
        indexer.preview(contents[2]) { text in XCTAssertNil(text); invalidated.fulfill() }
        await fulfillment(of: [started], timeout: 3)
        indexer.removeAll()
        await fulfillment(of: [invalidated], timeout: 3)
        indexer.index(contents[0]) { text in XCTAssertEqual(text, "fresh"); fresh.fulfill() }
        indexer.index(contents[1], allowLarge: true) { text in
            XCTAssertEqual(text, "fresh"); fresh.fulfill()
        }
        indexer.preview(contents[2]) { text in XCTAssertEqual(text, "fresh"); fresh.fulfill() }
        for _ in contents { gate.signal() }
        await fulfillment(of: [fresh], timeout: 3)
        for content in contents {
            let cached = expectation(description: "new result retained")
            indexer.index(content) { text in XCTAssertEqual(text, "fresh"); cached.fulfill() }
            await fulfillment(of: [cached], timeout: 3)
            lock.lock()
            XCTAssertEqual(calls[content.id], 2)
            lock.unlock()
        }
    }

    @MainActor
    func testClearSkipsQueuedStalePreviewBeforeParsing() async {
        let blocking = html("blocking")
        let queued = html("queued")
        let fresh = html("fresh")
        let entered = expectation(description: "first preview started")
        let invalidated = expectation(description: "old requests discarded")
        invalidated.expectedFulfillmentCount = 2
        let delivered = expectation(description: "fresh preview delivered")
        let gate = DispatchSemaphore(value: 0)
        let queuedParsed = DispatchSemaphore(value: 0)
        let indexer = RichSearchIndexer { content in
            if content.id == blocking.id {
                entered.fulfill()
                _ = gate.wait(timeout: .now() + 5)
            }
            if content.id == queued.id { queuedParsed.signal() }
            return content.description
        }
        indexer.preview(blocking) { text in XCTAssertNil(text); invalidated.fulfill() }
        indexer.preview(queued) { text in XCTAssertNil(text); invalidated.fulfill() }
        await fulfillment(of: [entered], timeout: 2)
        indexer.removeAll()
        await fulfillment(of: [invalidated], timeout: 2)
        indexer.preview(fresh) { text in XCTAssertEqual(text, "fresh"); delivered.fulfill() }
        gate.signal()
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(queuedParsed.wait(timeout: .now()), .timedOut,
            "Cleared queued data must not be parsed after clear")
    }

    @MainActor
    func testClearWithHistoryInvalidatesRichCache() async {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        let content = html("history")
        let item = ClipboardHistoryItem(timestamp: .now, contents: [content], sourceApplication: nil)
        monitor.applyHistoryItem(item, persist: false)
        XCTAssertFalse(monitor.history.isEmpty)
        let first = expectation(description: "warm cache")
        RichSearchIndexer.shared.index(content) { _ in first.fulfill() }
        await fulfillment(of: [first], timeout: 3)
        let invalidated = expectation(description: "cached callback invalidated on nonempty clear")
        RichSearchIndexer.shared.preview(content) { text in
            XCTAssertNil(text)
            invalidated.fulfill()
        }
        monitor.clearHistory()
        XCTAssertTrue(monitor.history.isEmpty)
        await fulfillment(of: [invalidated], timeout: 3)
    }

    private func html(_ value: String) -> ClipboardContent {
        ClipboardContent(data: Data("<b>\(value)</b>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: value)
    }
}
