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

    func testRepeatedPrefixFuzzyQueryIsBounded() {
        let sizes = [1_000, 3_000, 10_000]
        for size in sizes {
            let history = makeHistory(texts: [String(repeating: "a", count: size) + "-b"])
            let start = ContinuousClock.now
            let results = QuickSearchQuery.results(in: history, matching: "ab")
            let elapsed = milliseconds(start.duration(to: .now))
            print("QUICK_SEARCH_REPEATED_PREFIX size=\(size) raw_ms=\(elapsed)")
            XCTAssertEqual(results.map(\.id), history.map(\.id))
        }
    }

    func testPathologicalRepeatedPrefixFuzzyQueryCompletesWithinOneSecond() {
        let history = makeHistory(texts: [String(repeating: "a", count: 99_997) + "-b"])
        let start = ContinuousClock.now
        let results = QuickSearchQuery.results(in: history, matching: "ab")
        let elapsed = milliseconds(start.duration(to: .now))
        print("QUICK_SEARCH_REPEATED_PREFIX size=99997 raw_ms=\(elapsed)")
        XCTAssertEqual(results.map(\.id), history.map(\.id))
        XCTAssertLessThan(elapsed, 1_000)
    }

    func testFuzzyRankingOnRepeatedPrefixesPreservesWordStartsSpanAndRecency() {
        let history = makeHistory(texts: [
            "a---b", "a--b", "a b", "axxb", "a b", "ab", "abx", "AB"
        ])
        let results = QuickSearchQuery.results(in: history, matching: "a b")
        XCTAssertEqual(results.map(\.id), [history[2].id, history[4].id])

        let fuzzy = makeHistory(texts: ["a---b", "a--b", "a b", "axxb", "a b"])
        // A word-start match beats a tighter span, then tighter span wins.
        XCTAssertEqual(
            QuickSearchQuery.results(in: fuzzy, matching: "ab").map(\.id),
            [fuzzy[2].id, fuzzy[4].id, fuzzy[1].id, fuzzy[0].id, fuzzy[3].id]
        )
    }

    func testUserSelectionSurvivesLateRichIndexAndClipboardCapture() {
        let history = makeHistory(texts: ["new capture", "chosen older entry"])
        XCTAssertEqual(QuickSearchQuery.selection(from: history, preferredID: history[1].id,
            currentItemID: history[0].id, query: "")?.id, history[1].id)
        XCTAssertEqual(QuickSearchQuery.selection(from: history, preferredID: history[1].id,
            currentItemID: history[0].id, query: "entry")?.id, history[1].id)
        XCTAssertEqual(QuickSearchQuery.selection(from: [history[0]], preferredID: history[1].id,
            currentItemID: history[0].id, query: "")?.id, history[0].id)
    }

    func testLongOrdinaryFuzzyQueryPrefersLaterWordStarts() {
        let letters = String(repeating: "a", count: 65)
        let query = letters + "b"
        let early = "x" + letters + "-b"
        let history = makeHistory(texts: [early, early + " " + letters + "-b"])
        XCTAssertEqual(QuickSearchQuery.results(in: history, matching: query).map(\.id),
                       [history[1].id, history[0].id])
    }

    func testRepeatedQueryCharactersUseDistinctPositions() {
        let history = makeHistory(texts: ["a-a", "a--a", "a", "a--a--a", "a---a"])
        XCTAssertEqual(
            QuickSearchQuery.results(in: history, matching: "aa").map(\.id),
            [history[0].id, history[1].id, history[3].id, history[4].id]
        )
    }

    func testLongContiguousPrefixSearchIsBounded() {
        let text = String(repeating: "a", count: 20_000) + "b"
        let query = String(repeating: "a", count: 2_000) + "b"
        let history = makeHistory(texts: [text])
        let start = ContinuousClock.now
        XCTAssertEqual(QuickSearchQuery.results(in: history, matching: query).map(\.id),
                       history.map(\.id))
        let elapsed = milliseconds(start.duration(to: .now))
        print("QUICK_SEARCH_CONTIGUOUS_PREFIX raw_ms=\(elapsed)")
        XCTAssertLessThan(elapsed, 1_000)
    }

    private func makeHistory(texts: [String]) -> [ClipboardHistoryItem] {
        texts.enumerated().map { index, text in
            ClipboardHistoryItem(
                timestamp: Date(timeIntervalSince1970: Double(texts.count - index)),
                contents: [ClipboardContent(
                    data: Data(text.utf8),
                    formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                    description: text
                )],
                sourceApplication: nil
            )
        }
    }

    @MainActor
    func testSuccessiveColdLargeQueriesKeepMainActorResponsive() async {
        ClipboardSearchTextCache.shared.removeAll()
        let history = (0..<100).map { index in
            let text = String(repeating: "x", count: 1_000_000) + " marker-\(index)"
            return ClipboardHistoryItem(timestamp: .now,
                contents: [ClipboardContent(data: Data(text.utf8),
                    formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                    description: "Large text")], sourceApplication: nil)
        }
        for query in ["marker-1", "marker-99", "absent"] {
            let start = ContinuousClock.now
            let results = await QuickSearchWorker.results(in: history, query: query,
                richText: [:], ticket: QuickSearchWorker.invalidate())
            let elapsed = milliseconds(start.duration(to: .now))
            print("QUICK_SEARCH_DISTINCT_COLD query=\(query) raw_ms=\(elapsed)")
            let expected = history.enumerated().filter { "marker-\($0.offset)".contains(query) }
                .map(\.element.id)
            XCTAssertEqual(results.map(\.id), expected)
        }
    }

    @MainActor
    func testSupersededQueryCannotPublishResults() async {
        let history = makeHistory(texts: ["first", "second"])
        let stale = QuickSearchWorker.invalidate()
        let current = QuickSearchWorker.invalidate()
        let oldResults = await QuickSearchWorker.results(in: history, query: "first",
            richText: [:], ticket: stale)
        let newResults = await QuickSearchWorker.results(in: history, query: "second",
            richText: [:], ticket: current)
        XCTAssertTrue(oldResults.isEmpty)
        XCTAssertEqual(newResults.map(\.id), [history[1].id])
    }

    @MainActor
    func testBlockedHTMLIndexDoesNotBlockPlainSearchOrMainActor() async {
        let html = ClipboardContent(data: Data("<b>rich needle</b>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: "HTML")
        let plain = ClipboardContent(data: Data("plain needle".utf8),
            formats: [ClipboardFormat(uti: "public.utf8-plain-text")], description: "Text")
        let richItem = ClipboardHistoryItem(timestamp: .now, contents: [html], sourceApplication: nil)
        let plainItem = ClipboardHistoryItem(timestamp: .now, contents: [plain], sourceApplication: nil)
        let started = expectation(description: "Rich import started")
        let finished = expectation(description: "Rich import finished")
        let gate = DispatchSemaphore(value: 0)
        let indexer = RichSearchIndexer { _ in
            started.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            return "rich needle"
        }
        indexer.index(html) { text in
            XCTAssertEqual(text, "rich needle")
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        let start = ContinuousClock.now
        let results = await QuickSearchWorker.results(in: [plainItem, richItem],
            query: "plain", richText: [:], ticket: QuickSearchWorker.invalidate())
        let elapsed = start.duration(to: .now)
        XCTAssertEqual(results.map(\.id), [plainItem.id])
        XCTAssertLessThan(elapsed, .seconds(1), "Plain search must not wait for HTML import")
        gate.signal()
        await fulfillment(of: [finished], timeout: 2)
        let richResults = await QuickSearchWorker.results(in: [plainItem, richItem],
            query: "rich", richText: [html.id: "rich needle"], ticket: QuickSearchWorker.invalidate())
        XCTAssertEqual(richResults.map(\.id), [richItem.id])
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
