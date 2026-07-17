import AppKit
import XCTest

@testable import spaperclip

final class PerformanceTests: XCTestCase {
    private let plainText = ClipboardFormat(uti: "public.utf8-plain-text")

    func testCompleteLargeTextIsDecodedWithoutTruncation() {
        let expected = String(repeating: "Large UTF-8 text 🌍\n", count: 60_000)
        let content = ClipboardContent(
            data: Data(expected.utf8),
            formats: [plainText],
            description: "large text"
        )

        XCTAssertEqual(content.textForDisplay(), expected)
    }

    func testStaleAndCancelledLoadsCannotApply() {
        let coordinator = LazyTextView.TextLoadingCoordinator()
        let staleToken = coordinator.beginLoading()
        let currentToken = coordinator.beginLoading()

        XCTAssertFalse(coordinator.shouldApply(staleToken))
        XCTAssertTrue(coordinator.shouldApply(currentToken))

        coordinator.cancelLoading()
        XCTAssertFalse(coordinator.shouldApply(currentToken))
    }

    func testIconCacheLoadsEachBundleIdentifierOnce() {
        var loadCount = 0
        let expected = NSImage(size: NSSize(width: 16, height: 16))
        let cache = SourceApplicationIconCache { _ in
            loadCount += 1
            return expected
        }

        for _ in 0..<100 {
            XCTAssertTrue(cache.icon(for: "com.example.cached") === expected)
        }

        XCTAssertEqual(loadCount, 1)
    }

    func testMeasuredLargeTextDisplayPerformance() {
        let expected = String(repeating: "abcdefghij", count: 100_000)
        let content = ClipboardContent(
            data: Data(expected.utf8), formats: [plainText], description: "1 MB text")

        let textView = NSTextView()
        textView.string = content.textForDisplay() ?? "" // warmup
        let samples = measureSamples(count: 5) {
            textView.string = content.textForDisplay() ?? ""
            XCTAssertEqual(textView.string, expected)
        }
        report("1 MB production decode and NSTextView assignment", samples)

        XCTAssertLessThan(median(samples), 0.160, "1 MB median must remain below 160 ms")
    }

    func testMeasuredCachedIconReadPerformance() {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let cache = SourceApplicationIconCache { _ in icon }
        XCTAssertNotNil(cache.icon(for: "com.example.performance")) // warmup

        let samples = measureSamples(count: 5) {
            for _ in 0..<100 {
                XCTAssertNotNil(cache.icon(for: "com.example.performance"))
            }
        }
        report("100 production cached icon reads", samples)

        XCTAssertLessThan(median(samples), 0.00225, "100 cached reads must remain below 2.25 ms")
    }

    private func measureSamples(count: Int, operation: () -> Void) -> [TimeInterval] {
        (0..<count).map { _ in
            let start = ContinuousClock.now
            operation()
            let duration = start.duration(to: .now)
            return Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1e18
        }
    }

    private func median(_ samples: [TimeInterval]) -> TimeInterval {
        samples.sorted()[samples.count / 2]
    }

    private func report(_ workload: String, _ samples: [TimeInterval]) {
        let milliseconds = samples.map { $0 * 1_000 }
        #if DEBUG
            let configuration = "Debug"
        #else
            let configuration = "Release"
        #endif
        print(
            "PERFORMANCE workload=\(workload) configuration=\(configuration) "
                + "raw_ms=\(milliseconds) median_ms=\(median(milliseconds))"
        )
    }

}
