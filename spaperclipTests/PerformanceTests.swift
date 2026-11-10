import AppKit
import SwiftUI
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

    func testPreviewLimitPreservesCharactersAndUnlimitedDisplay() {
        let text = "a👨‍👩‍👧‍👦e\u{301}z"
        let limited = LazyTextView.Preview(text, maximumCharacters: 3)
        XCTAssertEqual(limited.text, "a👨‍👩‍👧‍👦e\u{301}")
        XCTAssertTrue(limited.isTruncated)
        let exact = LazyTextView.Preview(text, maximumCharacters: 4)
        XCTAssertEqual(exact.text, text)
        XCTAssertFalse(exact.isTruncated)
        let unlimited = LazyTextView.Preview(text, maximumCharacters: nil)
        XCTAssertEqual(unlimited.text, text)
        XCTAssertFalse(unlimited.isTruncated)
    }

    @MainActor
    func testLargeHTMLAndPlainQuickSearchPreviewsKeepLayoutBoundedAndRestoreCompleteText() async {
        // A single paragraph forces TextKit to shape far beyond the visible lines.
        // Exercise the real representable, including its asynchronous load.
        let fullText = String(repeating: "abcdefghij ", count: 100_000) + "end-marker"
        for uti in ["public.html", "public.utf8-plain-text"] {
            let source = uti == "public.html" ? "<p>\(fullText)</p>" : fullText
            let data = Data(source.utf8)
            let content = ClipboardContent(data: data, formats: [ClipboardFormat(uti: uti)],
                                           description: "Large paragraph")
            let loaded = expectation(description: "\(uti) partial preview loaded")
            let hosting = NSHostingView(rootView: LazyTextView(
                content: content, isEditable: false, maximumPreviewCharacters: 20_000,
                isPreviewTruncated: Binding(get: { false }, set: { truncated in
                    XCTAssertTrue(truncated)
                    loaded.fulfill()
                })))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            await fulfillment(of: [loaded], timeout: 5)
            guard let scroll = descendantScrollView(in: hosting),
                  let textView = scroll.documentView as? NSTextView,
                  let layout = textView.layoutManager, let container = textView.textContainer else {
                return XCTFail("Expected the production text preview")
            }
            XCTAssertEqual(textView.string, String(fullText.prefix(20_000)))
            let samples = measureSamples(count: 5) {
                layout.invalidateLayout(forCharacterRange: NSRange(location: 0,
                    length: textView.string.utf16.count), actualCharacterRange: nil)
                layout.ensureLayout(forBoundingRect: NSRect(x: 0, y: 0, width: 424, height: 400),
                                    in: container)
            }
            report("\(uti) Quick Search visible paragraph layout", samples)
            XCTAssertLessThan(median(samples), 0.100)

            let item = ClipboardHistoryItem(timestamp: .now, contents: [content], sourceApplication: nil)
            let restored = await PlainRestoreWorker.text(from: item)
            XCTAssertEqual(restored, fullText)
            let board = NSPasteboard(name: .init("bounded-preview-\(UUID())"))
            defer { board.releaseGlobally() }
            XCTAssertTrue(Utilities.copyAllContentTypes(from: item, to: board))
            XCTAssertEqual(board.data(forType: .init(uti)), data)
            window.contentView = nil
        }
    }

    @MainActor
    private func descendantScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.descendantScrollView(in: $0) }.first
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
