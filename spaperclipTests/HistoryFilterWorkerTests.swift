import Foundation
import XCTest
@testable import spaperclip

final class HistoryFilterWorkerTests: XCTestCase {
    private func item(_ text: String, uti: String = "public.utf8-plain-text") -> ClipboardHistoryItem {
        ClipboardHistoryItem(timestamp: .now, contents: [ClipboardContent(
            data: Data(text.utf8), formats: [ClipboardFormat(uti: uti)], description: text
        )], sourceApplication: nil)
    }

    func testHistoryWorkerReturnsPlainMatchesWhileRichIndexIsBlocked() async {
        let rich = item("<b>needle</b>", uti: "public.html")
        let plain = item("a NEEDLE in plain text")
        let entered = expectation(description: "rich import entered")
        let release = DispatchSemaphore(value: 0)
        let indexer = RichSearchIndexer { _ in
            entered.fulfill()
            release.wait()
            return "needle"
        }
        indexer.index(rich.contents[0]) { _ in }
        await fulfillment(of: [entered], timeout: 2)
        let worker = HistoryFilterWorker()
        let result = await worker.results(in: [rich, plain], query: "needle",
                                          richText: [:], ticket: worker.invalidate())
        XCTAssertEqual(result.map(\.id), [plain.id])
        release.signal()
    }

    func testWorkerPreservesSubstringOrderAndUsesIndexedRichText() async {
        let rich = item("<b>other</b>", uti: "public.html")
        let plain = item("Late NEEDLE text")
        let other = item("needle-free")
        let worker = HistoryFilterWorker()
        let matches = await worker.results(in: [rich, plain, other], query: "needle",
            richText: [rich.contents[0].id: "rich Needle"], ticket: worker.invalidate())
        XCTAssertEqual(matches.map(\.id), [rich.id, plain.id, other.id])
        let stale = worker.invalidate()
        _ = worker.invalidate()
        let discarded = await worker.results(in: [plain], query: "needle", richText: [:], ticket: stale)
        XCTAssertTrue(discarded.isEmpty)
    }

    func testCancelledPlainRestoreCannotLeavePendingOrFinishAReplacement() {
        var restore = HistoryPlainRestoreState()
        let firstItem = UUID()
        let secondItem = UUID()
        let first = restore.begin(for: firstItem)
        XCTAssertTrue(restore.isPending)
        XCTAssertEqual(restore.itemID, firstItem)

        // Selection changed while the first worker was still decoding.
        restore.cancel()
        XCTAssertFalse(restore.isPending)
        let second = restore.begin(for: secondItem)
        XCTAssertFalse(restore.finish(first))
        XCTAssertTrue(restore.isPending)
        XCTAssertEqual(restore.pendingID, second)
        XCTAssertEqual(restore.itemID, secondItem)
        XCTAssertTrue(restore.finish(second))
        XCTAssertFalse(restore.isPending)
        XCTAssertNil(restore.itemID)
    }

    func testOldPlainRestoreCannotFinishAfterRichRestoreCancelsIt() {
        var restore = HistoryPlainRestoreState()
        let first = restore.begin(for: UUID())
        restore.cancel() // Return chose a full-fidelity restore instead.
        XCTAssertFalse(restore.finish(first))
        XCTAssertFalse(restore.isPending)
    }

    func testSynchronousHistoryFilterCanWaitOnAnInFlightRichImport() {
        let rich = item("<b>needle</b>", uti: "public.html")
        let cache = ClipboardSearchTextCache(totalCostLimit: 1024)
        let entered = expectation(description: "rich import entered")
        let finished = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = cache.text(for: rich.contents[0]) {
                entered.fulfill()
                release.wait()
                return "needle"
            }
        }
        wait(for: [entered], timeout: 2)
        DispatchQueue.global().async {
            _ = ClipboardHistoryFilter.matching([rich], searchText: "needle", cache: cache)
            finished.signal()
        }
        // The old synchronous filter waits for a rich import already in flight.
        XCTAssertEqual(finished.wait(timeout: .now() + 0.1), .timedOut)
        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
    }
}
