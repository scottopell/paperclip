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

    func testIndexedRichTextOverSizeBoundUsesContiguousMatchWithoutFuzzyRanking() {
        let content = ClipboardContent(data: Data("<p>small</p>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: "rich")
        let item = ClipboardHistoryItem(timestamp: .now, contents: [content], sourceApplication: nil)
        let text = String(repeating: "a", count: 120_000) + "-b"
        XCTAssertEqual(QuickSearchQuery.results(in: [item], matching: "ab",
            indexedRichText: [content.id: text]).count, 0)
        XCTAssertEqual(QuickSearchQuery.results(in: [item], matching: "a-b",
            indexedRichText: [content.id: text]).map(\.id), [item.id])
    }

    func testIndexedRichTextKeepsDiacriticInsensitiveMatchesAcrossSizeBound() {
        let content = ClipboardContent(data: Data("<b>résumé</b>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: "HTML")
        let item = ClipboardHistoryItem(timestamp: .now, contents: [content], sourceApplication: nil)
        for text in ["résumé", String(repeating: "x", count: 100_000) + "résumé"] {
            XCTAssertEqual(QuickSearchQuery.results(in: [item], matching: "resume",
                indexedRichText: [content.id: text]).map(\.id), [item.id])
        }
    }

    func testPlainRestoreSelectionInvalidatesOnlyWhenItemChanges() {
        let first = UUID()
        let second = UUID()
        XCTAssertFalse(QuickSearchPlainRestoreSelection.invalidates(
            activeItemID: first, selectedItemID: first))
        XCTAssertTrue(QuickSearchPlainRestoreSelection.invalidates(
            activeItemID: first, selectedItemID: second))
        XCTAssertTrue(QuickSearchPlainRestoreSelection.invalidates(
            activeItemID: first, selectedItemID: nil))
        XCTAssertFalse(QuickSearchPlainRestoreSelection.invalidates(
            activeItemID: nil, selectedItemID: second))
        // An onChange for the old item must not cancel a restore started for the new one.
        XCTAssertFalse(QuickSearchPlainRestoreSelection.invalidates(
            activeItemID: second, selectedItemID: second))
    }

    func testPlainRestoreSurvivesSameQueryRefreshWhileItsItemIsLive() {
        let selected = UUID()
        let newCapture = UUID()
        XCTAssertFalse(QuickSearchPlainRestoreSelection.invalidatesRefresh(
            activeItemID: selected, queryChanged: false, liveItemIDs: [selected]))
        XCTAssertFalse(QuickSearchPlainRestoreSelection.invalidatesRefresh(
            activeItemID: selected, queryChanged: false, liveItemIDs: [newCapture, selected]))
        XCTAssertTrue(QuickSearchPlainRestoreSelection.invalidatesRefresh(
            activeItemID: selected, queryChanged: false, liveItemIDs: [newCapture]))
        XCTAssertTrue(QuickSearchPlainRestoreSelection.invalidatesRefresh(
            activeItemID: selected, queryChanged: true, liveItemIDs: [selected]))
        XCTAssertFalse(QuickSearchPlainRestoreSelection.invalidatesRefresh(
            activeItemID: nil, queryChanged: true, liveItemIDs: []))
    }

    func testAsyncRestoreRequiresTheSamePasteboardChangeCount() {
        let board = NSPasteboard(name: .init("spaperclip-restore-test-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        XCTAssertTrue(board.setString("before", forType: .string))
        let count = board.changeCount
        XCTAssertTrue(ClipboardRestorePrecondition.isSafe(to: board,
            expectedChangeCount: count, capturePending: false, captureIncomplete: false))
        XCTAssertFalse(ClipboardRestorePrecondition.isSafe(to: board,
            expectedChangeCount: count, capturePending: true, captureIncomplete: false))
        XCTAssertFalse(ClipboardRestorePrecondition.isSafe(to: board,
            expectedChangeCount: count, capturePending: false, captureIncomplete: true))
        board.clearContents()
        XCTAssertTrue(board.setString("new owner", forType: .string))
        XCTAssertFalse(ClipboardRestorePrecondition.isSafe(to: board,
            expectedChangeCount: count, capturePending: false, captureIncomplete: false))
        XCTAssertEqual(board.string(forType: .string), "new owner")
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

    func testHTMLExtractorSkipsNonTextResourcesAndDecodesEntities() {
        let html = """
            <html><head><title>hidden</title><style>.x { color: red }</style></head>
            <body><p>first &amp; second</p><script>evil()</script>
            <div>hello <strong>world</strong><img src="https://example.invalid/no-request.png"></div>
            </body></html>
            """
        let text = LocalHTMLText.decode(Data(html.utf8))
        XCTAssertEqual(text, "first & second\nhello world")
        XCTAssertFalse(text?.contains("hidden") == true)
        XCTAssertFalse(text?.contains("evil()") == true)
        XCTAssertEqual(LocalHTMLText.decode(Data("<p>hello </p><p>world</p>".utf8)),
                       "hello\nworld")
        XCTAssertEqual(LocalHTMLText.decode(Data("<div>hello <strong>world</strong></div>".utf8)),
                       "hello world")
        XCTAssertEqual(LocalHTMLText.decode(Data("<pre>  a\n b </pre>".utf8)),
                       "  a\n b ")
    }

    @MainActor
    func testHTMLOnlyUsesOfflineParserForIndexPreviewAndPlainRestore() async {
        let html = ClipboardContent(data: Data("<b>résumé ✅</b>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: "HTML")
        let item = ClipboardHistoryItem(timestamp: .now, contents: [html], sourceApplication: nil)
        XCTAssertTrue(html.usesLocalHTMLText)
        XCTAssertEqual(html.searchableText(), "résumé ✅")
        XCTAssertEqual(html.getTextChunk(offset: 0, length: 100)?.text, "résumé ✅")
        XCTAssertEqual(html.textForDisplay(), "résumé ✅")

        let loaded = expectation(description: "Local HTML parsing completed")
        RichSearchIndexer.shared.index(html) { text in
            XCTAssertTrue(text?.contains("résumé ✅") == true)
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 10)
        let preview = await ClipboardPreviewText.chunk(for: html, length: 100)
        let restored = await PlainRestoreWorker.text(from: item)
        XCTAssertTrue(preview?.contains("résumé") == true)
        XCTAssertTrue(restored?.contains("résumé ✅") == true)
    }

    @MainActor
    func testBlockedPreviewAndDetailCannotStarveRichIndex() async {
        let previewContent = ClipboardContent(data: Data("<b>preview</b>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: "Preview")
        let detailContent = ClipboardContent(data: Data("<b>detail</b>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: "Detail")
        let searchContent = ClipboardContent(data: Data("<b>search</b>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: "Search")
        let blocked = expectation(description: "preview and detail started")
        blocked.expectedFulfillmentCount = 2
        let searched = expectation(description: "search completed while other lanes blocked")
        let completed = expectation(description: "blocked reads completed")
        completed.expectedFulfillmentCount = 2
        let gate = DispatchSemaphore(value: 0)
        let indexer = RichSearchIndexer { content in
            if content.id != searchContent.id {
                blocked.fulfill()
                _ = gate.wait(timeout: .now() + 5)
            }
            return content.description
        }
        indexer.preview(previewContent) { _ in completed.fulfill() }
        indexer.index(detailContent, allowLarge: true) { _ in completed.fulfill() }
        await fulfillment(of: [blocked], timeout: 2)
        indexer.index(searchContent) { text in
            XCTAssertEqual(text, "Search")
            searched.fulfill()
        }
        await fulfillment(of: [searched], timeout: 2)
        gate.signal()
        gate.signal()
        await fulfillment(of: [completed], timeout: 2)
    }

    @MainActor
    func testConcurrentSameContentRichRequestsShareDecode() async {
        let html = ClipboardContent(data: Data("<b>shared</b>".utf8),
            formats: [ClipboardFormat(uti: "public.html")], description: "Shared")
        let started = expectation(description: "one decode started")
        let finished = expectation(description: "both requests completed")
        finished.expectedFulfillmentCount = 2
        let gate = DispatchSemaphore(value: 0)
        let decodes = DispatchSemaphore(value: 0)
        let indexer = RichSearchIndexer { _ in
            decodes.signal()
            started.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            return "shared"
        }
        indexer.index(html) { text in
            XCTAssertEqual(text, "shared")
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        indexer.preview(html) { text in
            XCTAssertEqual(text, "shared")
            finished.fulfill()
        }
        gate.signal()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(exactlyOneSignal(decodes))
    }

    @MainActor
    func testLargeHTMLPreviewDoesNotExpandSearchBound() async {
        let html = ClipboardContent(data: Data(("<p>start</p>" + String(repeating: " ", count: 500_000)
            + "<p>end</p>").utf8), formats: [ClipboardFormat(uti: "public.html")],
            description: "Large HTML")
        let indexed = expectation(description: "large HTML omitted from search")
        RichSearchIndexer.shared.index(html) { text in
            XCTAssertNil(text)
            indexed.fulfill()
        }
        await fulfillment(of: [indexed], timeout: 2)
        let preview = await ClipboardPreviewText.chunk(for: html, length: 100)
        XCTAssertEqual(preview, "start\nend")
    }

    @MainActor
    func testOversizeHTMLStillRestoresOriginalRepresentation() async {
        let data = Data(repeating: 65, count: LocalHTMLText.maximumImportBytes + 1)
        let content = ClipboardContent(data: data, formats: [ClipboardFormat(uti: "public.html")],
            description: "Oversize HTML")
        let item = ClipboardHistoryItem(timestamp: .now, contents: [content], sourceApplication: nil)
        XCTAssertNil(LocalHTMLText.decode(data))
        let preview = await ClipboardPreviewText.chunk(for: content, length: 100)
        let transformed = await PlainRestoreWorker.text(from: item)
        XCTAssertNil(preview)
        XCTAssertNil(transformed)
        XCTAssertEqual(ClipboardHistoryPreview.fallbackText(for: item), "(HTML too large to preview)")
        let board = NSPasteboard(name: .init("oversize-html-\(UUID())"))
        defer { board.releaseGlobally() }
        XCTAssertTrue(Utilities.copyAllContentTypes(from: item, to: board))
        XCTAssertEqual(board.data(forType: .init("public.html")), data)
    }

    @MainActor
    func testCancelledSlowPlainRestoreDoesNotBlockNextItem() async {
        let slow = ClipboardContent(data: Data("{\\rtf1 slow}".utf8),
            formats: [ClipboardFormat(uti: "public.rtf")], description: "slow")
        let plain = ClipboardContent(data: Data("next result".utf8),
            formats: [ClipboardFormat(uti: "public.utf8-plain-text")], description: "next")
        let entered = expectation(description: "slow rich conversion entered")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let stale = Task {
            await PlainRestoreWorker.text(from: slow) { _ in
                entered.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return "old result"
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        stale.cancel()
        let cancelled = await stale.value
        XCTAssertNil(cancelled)
        let next = await PlainRestoreWorker.text(from: plain)
        XCTAssertEqual(next, "next result")
    }

    @MainActor
    func testTwoBlockedRTFRestoresDoNotBlockPlainOrQueueAThird() async {
        let rtf = ClipboardContent(data: Data("{\\rtf1 blocked}".utf8),
            formats: [ClipboardFormat(uti: "public.rtf")], description: "RTF")
        let plain = ClipboardContent(data: Data("still available".utf8),
            formats: [ClipboardFormat(uti: "public.utf8-plain-text")], description: "Plain")
        let entered = expectation(description: "two conversions started")
        entered.expectedFulfillmentCount = 2
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); gate.signal() }
        let first = Task {
            await PlainRestoreWorker.text(from: rtf) { _ in
                entered.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return "first"
            }
        }
        let second = Task {
            await PlainRestoreWorker.text(from: rtf) { _ in
                entered.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return "second"
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        first.cancel()
        second.cancel()
        let a = await first.value
        let b = await second.value
        XCTAssertNil(a)
        XCTAssertNil(b)
        let available = await PlainRestoreWorker.text(from: plain)
        XCTAssertEqual(available, "still available")
        let third = await PlainRestoreWorker.text(from: rtf) { _ in
            XCTFail("A third RTF conversion must not wait behind two stuck calls")
            return "unexpected"
        }
        XCTAssertNil(third)
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

    private func exactlyOneSignal(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now()) == .success
            && semaphore.wait(timeout: .now()) == .timedOut
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
