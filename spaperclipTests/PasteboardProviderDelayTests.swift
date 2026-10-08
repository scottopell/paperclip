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
    func testFailedSnapshotDoesNotPollAgainButForceRetriesAndNewWriteCaptures() async {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("com.example.unreadable")
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        let previous = ClipboardHistoryItem(timestamp: Date(), contents: [
            ClipboardContent(data: Data("previous".utf8),
                             formats: [ClipboardFormat(uti: type.rawValue)], description: "previous")
        ], sourceApplication: nil)
        monitor.applyHistoryItem(previous, persist: false)
        let initialCount = board.changeCount
        board.clearContents()
        let provider = CountingMissingProvider()
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [type]))
        XCTAssertTrue(board.writeObjects([item]))
        XCTAssertNotEqual(board.changeCount, initialCount)
        monitor.reconcileCurrentPasteboard()
        let failed = expectation(for: NSPredicate { _, _ in monitor.captureIncomplete },
                                 evaluatedWith: nil)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertNil(monitor.currentItem)
        XCTAssertNil(monitor.currentItemID)
        XCTAssertEqual(monitor.selectedHistoryItem?.id, previous.id)
        XCTAssertEqual(monitor.history.count, 1)
        let callsAfterFailure = provider.calls
        for _ in 0..<3 { monitor.reconcileCurrentPasteboard() } // Poll unchanged snapshot.
        XCTAssertEqual(provider.calls, callsAfterFailure, "unchanged failed snapshot must not be retried")
        XCTAssertFalse(monitor.isCapturingHistory)

        // AppKit may cache a missing promised representation. Force still schedules one
        // explicit read, but cannot make that provider produce bytes on the same write.
        monitor.reconcileCurrentPasteboard(force: true)
        XCTAssertTrue(monitor.isCapturingHistory)
        let retried = expectation(for: NSPredicate { _, _ in !monitor.isCapturingHistory },
                                  evaluatedWith: nil)
        await fulfillment(of: [retried], timeout: 5)
        XCTAssertTrue(monitor.captureIncomplete)
        XCTAssertNil(monitor.currentItemID)
        XCTAssertEqual(monitor.history.count, 1)

        let latest = Data([23, 0, 254])
        board.clearContents()
        XCTAssertTrue(board.setData(latest, forType: type))
        monitor.reconcileCurrentPasteboard()
        XCTAssertNil(monitor.currentItemID)
        let published = expectation(for: NSPredicate { _, _ in monitor.currentItem?.contents.first?.data == latest },
                                    evaluatedWith: nil)
        await fulfillment(of: [published], timeout: 5)
        XCTAssertEqual(monitor.currentItemID, monitor.history.first?.id)
    }

    @MainActor
    func testChangedClipboardClearsCurrentButKeepsBrowsingSelectionWhileProviderBlocks() async {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("public.utf8-plain-text")
        let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
        let previous = ClipboardHistoryItem(timestamp: Date(), contents: [
            ClipboardContent(data: Data("previous".utf8),
                             formats: [ClipboardFormat(uti: type.rawValue)], description: "previous")
        ], sourceApplication: nil)
        monitor.applyHistoryItem(previous, persist: false)
        let initialCount = board.changeCount
        board.clearContents()
        let began = expectation(description: "provider invoked")
        let gate = DispatchSemaphore(value: 0)
        let provider = BlockingProvider(began: began, gate: gate)
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [type]))
        XCTAssertTrue(board.writeObjects([item]))
        XCTAssertNotEqual(board.changeCount, initialCount)
        monitor.reconcileCurrentPasteboard()
        XCTAssertNil(monitor.currentItem, "old item is no longer on the pasteboard")
        XCTAssertNil(monitor.currentItemID)
        XCTAssertEqual(monitor.selectedHistoryItem?.id, previous.id)
        await fulfillment(of: [began], timeout: 3)
        gate.signal()
        let published = expectation(for: NSPredicate { _, _ in monitor.currentItem != nil },
                                    evaluatedWith: nil)
        await fulfillment(of: [published], timeout: 5)
        XCTAssertEqual(monitor.currentItem?.contents.first?.data, Data("stale bytes".utf8))
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

    private enum CopyEntry: String, CaseIterable {
        case format, content, allTypes, plainText

        @MainActor
        func copy(_ item: ClipboardHistoryItem, with monitor: ClipboardMonitor) -> Bool {
            let content = item.contents[0]
            switch self {
            case .format:
                return monitor.copyFormat(content.formats[0], from: content, in: item)
            case .content:
                return monitor.copyContent(content, in: item)
            case .allTypes:
                return monitor.copyAllContentTypes(item)
            case .plainText:
                return monitor.copyPlainTextOnly(item)
            }
        }
    }

    @MainActor
    private func savedItem(on monitor: ClipboardMonitor) -> ClipboardHistoryItem {
        let item = ClipboardHistoryItem(timestamp: Date(timeIntervalSince1970: 1), contents: [
            ClipboardContent(data: Data("saved text".utf8),
                             formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                             description: "saved text")
        ], sourceApplication: nil)
        monitor.applyHistoryItem(item, persist: false)
        return item
    }

    @MainActor
    private func assertNotPromoted(_ item: ClipboardHistoryItem, by monitor: ClipboardMonitor,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(monitor.history.count, 1, file: file, line: line)
        XCTAssertEqual(monitor.history[0].timestamp, item.timestamp, file: file, line: line)
        XCTAssertEqual(monitor.selectedHistoryItem?.id, item.id, file: file, line: line)
        XCTAssertNil(monitor.currentItemID, file: file, line: line)
    }

    @MainActor
    func testCopyEntryPointsLeavePendingPromisedClipboardUntouched() async {
        for entry in CopyEntry.allCases {
            let board = NSPasteboard(name: .init(UUID().uuidString))
            defer { board.releaseGlobally() }
            let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
            let saved = savedItem(on: monitor)
            let began = expectation(description: "\(entry.rawValue) provider invoked")
            let gate = DispatchSemaphore(value: 0)
            let provider = BlockingProvider(began: began, gate: gate)
            let type = NSPasteboard.PasteboardType("public.utf8-plain-text")
            let promised = NSPasteboardItem()
            XCTAssertTrue(promised.setDataProvider(provider, forTypes: [type]))
            board.clearContents()
            XCTAssertTrue(board.writeObjects([promised]))
            monitor.reconcileCurrentPasteboard(force: true)
            await fulfillment(of: [began], timeout: 3)
            let changeCount = board.changeCount
            let advertisedTypes = board.types

            XCTAssertFalse(entry.copy(saved, with: monitor), entry.rawValue)
            XCTAssertEqual(board.changeCount, changeCount, entry.rawValue)
            XCTAssertEqual(board.types, advertisedTypes, entry.rawValue)
            assertNotPromoted(saved, by: monitor)
            gate.signal()
            let finished = expectation(for: NSPredicate { _, _ in !monitor.isCapturingHistory },
                                       evaluatedWith: nil)
            await fulfillment(of: [finished], timeout: 5)
            XCTAssertEqual(board.data(forType: type), Data("stale bytes".utf8))
        }
    }

    @MainActor
    func testCopyEntryPointsLeaveIncompleteSnapshotUntouched() async {
        for entry in CopyEntry.allCases {
            let board = NSPasteboard(name: .init(UUID().uuidString))
            defer { board.releaseGlobally() }
            let monitor = ClipboardMonitor(loadPersistedHistory: false, pasteboard: board)
            let saved = savedItem(on: monitor)
            let readableType = NSPasteboard.PasteboardType("public.utf8-plain-text")
            let missingType = NSPasteboard.PasteboardType("com.example.unreadable")
            let external = Data("external bytes".utf8)
            let promised = NSPasteboardItem()
            let provider = MissingProvider()
            XCTAssertTrue(promised.setData(external, forType: readableType))
            XCTAssertTrue(promised.setDataProvider(provider, forTypes: [missingType]))
            board.clearContents()
            XCTAssertTrue(board.writeObjects([promised]))
            monitor.reconcileCurrentPasteboard(force: true)
            let failed = expectation(for: NSPredicate { _, _ in monitor.captureIncomplete },
                                     evaluatedWith: nil)
            await fulfillment(of: [failed], timeout: 5)
            let changeCount = board.changeCount

            XCTAssertFalse(entry.copy(saved, with: monitor), entry.rawValue)
            XCTAssertEqual(board.changeCount, changeCount, entry.rawValue)
            XCTAssertEqual(board.data(forType: readableType), external, entry.rawValue)
            XCTAssertTrue(board.types?.contains(missingType) == true, entry.rawValue)
            XCTAssertTrue(monitor.captureIncomplete, entry.rawValue)
            assertNotPromoted(saved, by: monitor)
        }
    }

    private final class CountingMissingProvider: NSObject, NSPasteboardItemDataProvider {
        private(set) var calls = 0

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                        provideDataForType type: NSPasteboard.PasteboardType) {
            calls += 1
        }
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
