import AppKit
import XCTest
@testable import spaperclip

/// Uses an isolated pasteboard so this test never replaces the user's clipboard.
final class PasteboardProviderDelayTests: XCTestCase {
    private final class SlowProvider: NSObject, NSPasteboardItemDataProvider {
        let payload: Data
        let delay: TimeInterval
        private(set) var calls = 0

        init(payload: Data, delay: TimeInterval) {
            self.payload = payload
            self.delay = delay
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                        provideDataForType type: NSPasteboard.PasteboardType) {
            calls += 1
            Thread.sleep(forTimeInterval: delay)
            item.setData(payload, forType: type)
        }
    }

    @MainActor
    func testMonitorCapturesProviderBytesWithoutBlockingMainQueue() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("public.utf8-plain-text")
        let payload = Data("exact promised bytes 👋".utf8)
        let provider = SlowProvider(payload: payload, delay: 0.3)
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [type]))
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: pasteboard)
        XCTAssertTrue(pasteboard.writeObjects([item]))
        XCTAssertTrue(pasteboard.types?.contains(type) == true)

        let started = ContinuousClock.now
        monitor.reconcileCurrentPasteboard(force: true)
        let elapsed = started.duration(to: .now)
        XCTAssertLessThan(elapsed, .milliseconds(150), "reconciliation must not read provider data on main")
        let captured = expectation(for: NSPredicate { _, _ in !monitor.history.isEmpty },
                                   evaluatedWith: nil)
        await fulfillment(of: [captured], timeout: 5)
        XCTAssertEqual(monitor.history.count, 1)
        XCTAssertEqual(monitor.history.first?.contents.first?.data, payload)
        XCTAssertEqual(monitor.currentItemID, monitor.history.first?.id)
        XCTAssertEqual(provider.calls, 1)
    }

    @MainActor
    func testChangedPasteboardDuringCapturePublishesOnlyLatestBytes() async {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("public.utf8-plain-text")
        let began = expectation(description: "first provider invoked")
        let gate = DispatchSemaphore(value: 0)
        let provider = BlockingProvider(began: began, gate: gate)
        let promised = NSPasteboardItem()
        XCTAssertTrue(promised.setDataProvider(provider, forTypes: [type]))
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        XCTAssertTrue(board.writeObjects([promised]))
        monitor.reconcileCurrentPasteboard(force: true)
        await fulfillment(of: [began], timeout: 3)
        let latest = Data("latest exact bytes".utf8)
        board.clearContents()
        XCTAssertTrue(board.setData(latest, forType: type))
        gate.signal()
        let published = expectation(for: NSPredicate { _, _ in !monitor.history.isEmpty },
            evaluatedWith: nil)
        await fulfillment(of: [published], timeout: 5)
        XCTAssertEqual(monitor.history.count, 1)
        XCTAssertEqual(monitor.history[0].contents[0].data, latest)
    }

    private final class BlockingProvider: NSObject, NSPasteboardItemDataProvider {
        let began: XCTestExpectation
        let gate: DispatchSemaphore

        init(began: XCTestExpectation, gate: DispatchSemaphore) {
            self.began = began
            self.gate = gate
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                        provideDataForType type: NSPasteboard.PasteboardType) {
            began.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            item.setData(Data("stale bytes".utf8), forType: type)
        }
    }

    @MainActor
    func testUnreadableAdvertisedTypeDoesNotSavePartialHistory() async {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let provider = MissingProvider()
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setData(Data("readable".utf8),
            forType: .init("public.utf8-plain-text")))
        XCTAssertTrue(item.setDataProvider(provider,
            forTypes: [.init("com.example.unreadable")]))
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        XCTAssertTrue(board.writeObjects([item]))
        monitor.reconcileCurrentPasteboard(force: true)
        let failed = expectation(for: NSPredicate { _, _ in monitor.captureIncomplete },
            evaluatedWith: nil)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertTrue(monitor.history.isEmpty)
        XCTAssertFalse(monitor.isCapturingHistory)
    }

    @MainActor
    func testClearHistoryInvalidatesInFlightCaptureEvenWhenHistoryIsEmpty() async {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let began = expectation(description: "capture started")
        let gate = DispatchSemaphore(value: 0)
        let provider = BlockingProvider(began: began, gate: gate)
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [.init("public.utf8-plain-text")]))
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        XCTAssertTrue(board.writeObjects([item]))
        monitor.reconcileCurrentPasteboard(force: true)
        await fulfillment(of: [began], timeout: 3)
        monitor.clearHistory()
        gate.signal()
        let done = expectation(for: NSPredicate { _, _ in !monitor.isCapturingHistory },
            evaluatedWith: nil)
        await fulfillment(of: [done], timeout: 5)
        monitor.reconcileCurrentPasteboard()
        XCTAssertTrue(monitor.history.isEmpty)
        XCTAssertFalse(monitor.isCapturingHistory)
    }

    private final class MissingProvider: NSObject, NSPasteboardItemDataProvider {
        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                        provideDataForType type: NSPasteboard.PasteboardType) {}
    }

    func testReadingPromisedDataOffMainThread() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("public.utf8-plain-text")
        let payload = Data("worker bytes".utf8)
        let provider = SlowProvider(payload: payload, delay: 0.15)
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [type]))
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let actual = await Task.detached { pasteboard.data(forType: type) }.value
        XCTAssertEqual(actual, payload)
        XCTAssertEqual(provider.calls, 1)
    }

    func testReadingPromisedDataBlocksTheCallingThreadAndPreservesBytes() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("public.utf8-plain-text")
        let payload = Data("provider's exact bytes 👋".utf8)
        let provider = SlowProvider(payload: payload, delay: 0.15)
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [type]))
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let start = ContinuousClock.now
        let actual = try XCTUnwrap(pasteboard.data(forType: type))
        let elapsed = start.duration(to: .now)
        XCTAssertEqual(actual, payload)
        XCTAssertEqual(provider.calls, 1)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(100))
        print("PASTEBOARD_PROVIDER_READ elapsed=\(elapsed)")
    }
}
