import Foundation
import XCTest

@testable import spaperclip

final class ClipboardSearchTextCacheTests: XCTestCase {
    private func content(_ uti: String = "public.rtf", data: Data = Data("bad rtf".utf8)) -> ClipboardContent {
        ClipboardContent(data: data, formats: [ClipboardFormat(uti: uti)], description: "test")
    }

    func testSlowDecodeDoesNotBlockAnotherItem() {
        let cache = ClipboardSearchTextCache(totalCostLimit: 1024)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let otherFinished = DispatchSemaphore(value: 0)
        let slow = content()
        let other = content("public.utf8-plain-text")

        DispatchQueue.global().async {
            _ = cache.text(for: slow) {
                entered.signal()
                _ = release.wait(timeout: .now() + 5)
                return "slow"
            }
            finished.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            _ = cache.text(for: other) { "fast" }
            otherFinished.signal()
        }
        let result = otherFinished.wait(timeout: .now() + 1)
        release.signal() // Always release the first decode, even on failure.
        XCTAssertEqual(result, .success, "unrelated text must not wait for slow decoding")
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
    }

    func testFailedRichDecodeIsCachedAndRemoveAllAllowsRetry() {
        let cache = ClipboardSearchTextCache(totalCostLimit: 1024)
        for uti in ["public.rtf", "public.html"] {
            let item = content(uti)
            var attempts = 0
            for _ in 0..<3 {
                XCTAssertNil(cache.text(for: item) {
                    attempts += 1
                    return nil
                })
            }
            XCTAssertEqual(attempts, 1, "failed \(uti) parse must not repeat")
            XCTAssertFalse(cache.matches("anything", in: item))
            XCTAssertEqual(cache.decodeCount(for: item), 0)
        }
        cache.removeAll()
        let item = content()
        var attempts = 0
        XCTAssertNil(cache.text(for: item) { attempts += 1; return nil })
        cache.removeAll()
        XCTAssertNil(cache.text(for: item) { attempts += 1; return nil })
        XCTAssertEqual(attempts, 2)
    }

    func testConcurrentReadersOfSameItemShareFailedDecode() {
        let cache = ClipboardSearchTextCache(totalCostLimit: 1024)
        let item = content()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = cache.text(for: item) {
                started.signal()
                _ = release.wait(timeout: .now() + 5)
                return nil
            }
            finished.signal()
        }
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            _ = cache.text(for: item) { "unexpected" }
            finished.signal()
        }
        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
        XCTAssertNil(cache.text(for: item) { "unexpected" })
    }

    func testPlainTextDecodeFailureIsNotNegativelyCached() {
        let cache = ClipboardSearchTextCache(totalCostLimit: 1024)
        let item = content("public.utf8-plain-text")
        XCTAssertNil(cache.text(for: item) { nil })
        XCTAssertEqual(cache.text(for: item) { "recovered" }, "recovered")
        XCTAssertEqual(cache.decodeCount(for: item), 1)
    }

    func testOversizedRichDataFailsWithoutParsing() {
        let cache = ClipboardSearchTextCache(totalCostLimit: 1024)
        for uti in ["public.rtf", "public.html"] {
            let item = content(uti, data: Data(repeating: 65, count: 500_000))
            XCTAssertNil(item.searchableText(cache: cache))
            XCTAssertFalse(cache.matches("anything", in: item))
        }
    }
}
