import XCTest

@testable import spaperclip

final class QuickSearchPerformanceTests: XCTestCase {
    func testImmediateQueryLatencyAndResultOrder() {
        let history = makeHistory(count: 100)
        let expectedIDs = history.filter { $0.textRepresentation?.contains("needle") == true }.map(\.id)
        _ = QuickSearchQuery.results(in: history, matching: "needle") // warmup

        let samples = (0..<5).map { _ in
            let start = ContinuousClock.now
            let results = QuickSearchQuery.results(in: history, matching: "needle")
            XCTAssertEqual(results.map(\.id), expectedIDs)
            let duration = start.duration(to: .now)
            return Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1e15
        }
        print("QUICK_SEARCH_CANDIDATE raw_ms=\(samples) median_ms=\(median(samples))")
        XCTAssertLessThan(median(samples), 50)
    }

    func testWarmLargeTextQueryLatencyAndLateResultOrder() {
        ClipboardSearchTextCache.shared.removeAll()
        let payloadSize = 1_000_000
        let history = (0..<100).map { index in
            let suffix = index.isMultiple(of: 10) ? " late-needle" : " no-match"
            let text = String(repeating: "x", count: payloadSize - suffix.count) + suffix
            return ClipboardHistoryItem(
                timestamp: Date(timeIntervalSince1970: Double(100 - index)),
                contents: [
                    ClipboardContent(
                        data: Data(text.utf8),
                        formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                        description: "large item \(index)"
                    )
                ],
                sourceApplication: nil
            )
        }
        let expectedIDs = history.enumerated().filter { $0.offset.isMultiple(of: 10) }.map(\.element.id)

        let coldStart = ContinuousClock.now
        let coldResults = QuickSearchQuery.results(in: history, matching: "late-needle")
        let coldMilliseconds = milliseconds(coldStart.duration(to: .now))
        XCTAssertEqual(coldResults.map(\.id), expectedIDs)

        let samples = (0..<5).map { _ in
            let start = ContinuousClock.now
            let results = QuickSearchQuery.results(in: history, matching: "late-needle")
            XCTAssertEqual(results.map(\.id), expectedIDs)
            return milliseconds(start.duration(to: .now))
        }
        print(
            "QUICK_SEARCH_LARGE cold_ms=\(coldMilliseconds) raw_warm_ms=\(samples) "
                + "median_warm_ms=\(median(samples))"
        )
        XCTAssertLessThan(median(samples), 50)
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
    }

    private func makeHistory(count: Int) -> [ClipboardHistoryItem] {
        (0..<count).map { index in
            let text = index.isMultiple(of: 10) ? "needle item \(index)" : "other item \(index)"
            return ClipboardHistoryItem(
                timestamp: Date(timeIntervalSince1970: Double(count - index)),
                contents: [
                    ClipboardContent(
                        data: Data(text.utf8),
                        formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                        description: text
                    )
                ],
                sourceApplication: nil
            )
        }
    }

    private func median(_ samples: [Double]) -> Double {
        samples.sorted()[samples.count / 2]
    }
}
