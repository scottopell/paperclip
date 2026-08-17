import AppKit
import XCTest

@testable import spaperclip

final class ClipboardMVPTests: XCTestCase {
    private func textItem(_ text: String) -> ClipboardHistoryItem {
        let content = ClipboardContent(
            data: Data(text.utf8),
            formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
            description: text
        )
        return ClipboardHistoryItem(
            timestamp: Date(),
            contents: [content],
            sourceApplication: nil
        )
    }

    func testAppDeclaresMenuBarAccessoryActivationPolicy() {
        let appBundle = Bundle(for: AppDelegate.self)

        XCTAssertEqual(
            appBundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool,
            true,
            "Paperclip should stay out of the Dock and application switcher"
        )
    }

    @MainActor
    func testSettingsWindowControllerOwnsReusableWindow() throws {
        let controller = SettingsWindowController()
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.title, "Paperclip Settings")
        XCTAssertFalse(window.isReleasedWhenClosed)

        controller.showSettings()
        XCTAssertTrue(window.isVisible)

        XCTAssertFalse(controller.windowShouldClose(window))
        XCTAssertFalse(window.isVisible)

        controller.showSettings()
        XCTAssertTrue(window.isVisible)
        window.orderOut(nil)
    }

    func testHistoryFilterIsCaseInsensitiveAndPreservesOrder() {
        let first = textItem("Alpha result")
        let second = textItem("unrelated")
        let third = textItem("another ALPHA result")

        let matches = ClipboardHistoryFilter.matching(
            [first, second, third],
            searchText: "alpha"
        )

        XCTAssertEqual(matches.map(\.id), [first.id, third.id])
    }

    func testHistoryFilterReturnsAllItemsForEmptySearch() {
        let history = [textItem("first"), textItem("second")]

        XCTAssertEqual(
            ClipboardHistoryFilter.matching(history, searchText: "").map(\.id),
            history.map(\.id)
        )
    }

    func testRelativeDateFormattingUsesScannableRecency() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        XCTAssertEqual(
            Utilities.formatRelativeDate(
                now.addingTimeInterval(-20), relativeTo: now, calendar: calendar
            ),
            "Just now"
        )
        XCTAssertEqual(
            Utilities.formatRelativeDate(
                now.addingTimeInterval(-5 * 60), relativeTo: now, calendar: calendar
            ),
            "5 min ago"
        )
        XCTAssertEqual(
            Utilities.formatRelativeDate(
                now.addingTimeInterval(-2 * 3_600), relativeTo: now, calendar: calendar
            ),
            "2 hrs ago"
        )
    }

    func testExactTimestampRemainsAvailable() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(Utilities.formatDate(date).isEmpty)
    }

    func testQuickSearchAccessibilityLabelCombinesStateAndContent() {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let item = ClipboardHistoryItem(
            timestamp: timestamp,
            contents: [
                ClipboardContent(
                    data: Data("pull request".utf8),
                    formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                    description: "pull request"
                )
            ],
            sourceApplication: SourceApplicationInfo(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari"
            )
        )

        let label = QuickSearchResultAccessibility.label(
            preview: "pull request",
            item: item,
            isSelected: true,
            isCurrent: true,
            now: timestamp.addingTimeInterval(5 * 60)
        )

        XCTAssertTrue(label.contains("Selected"))
        XCTAssertTrue(label.contains("Current clipboard item"))
        XCTAssertTrue(label.contains("5 min ago"))
        XCTAssertTrue(label.contains("from Safari"))
        XCTAssertTrue(label.contains("Text"))
        XCTAssertTrue(label.contains("pull request"))
    }

    func testQuickSearchFuzzyRankingPrefersExactThenContiguousThenGapped() {
        let fuzzy = textItem("Quick Search Result")
        let contiguous = textItem("prefix qsr suffix")
        let exact = textItem("QSR")
        let unrelated = textItem("clipboard history")

        let matches = QuickSearchQuery.results(
            in: [fuzzy, unrelated, contiguous, exact],
            matching: "qsr"
        )

        XCTAssertEqual(matches.map(\.id), [exact.id, contiguous.id, fuzzy.id])
    }

    func testQuickSearchFuzzyMatchingIsCaseAndDiacriticInsensitive() {
        let cafe = textItem("CAFÉ receipt")

        XCTAssertEqual(
            QuickSearchQuery.results(in: [cafe], matching: "cafe").map(\.id),
            [cafe.id]
        )
    }

    func testQuickSearchFuzzyRankingPrefersWordStarts() {
        let midWord = textItem("acmeb record")
        let wordStarts = textItem("alpha beta record")

        XCTAssertEqual(
            QuickSearchQuery.results(
                in: [midWord, wordStarts], matching: "abr"
            ).map(\.id),
            [wordStarts.id, midWord.id]
        )
    }

    func testQuickSearchEqualRanksKeepRecencyOrder() {
        let newer = textItem("quick search row")
        let older = textItem("quick search row")

        XCTAssertEqual(
            QuickSearchQuery.results(in: [newer, older], matching: "qsr").map(\.id),
            [newer.id, older.id]
        )
    }

    func testQuickSearchInitialSelectionUsesCurrentItemID() {
        let first = textItem("first")
        let current = textItem("current")
        let results = [first, current]

        XCTAssertEqual(
            QuickSearchQuery.initialSelection(
                from: results, currentItemID: current.id, query: "")?.id,
            current.id
        )
        XCTAssertEqual(
            QuickSearchQuery.initialSelection(
                from: results, currentItemID: current.id, query: "cur")?.id,
            first.id
        )
        XCTAssertEqual(
            QuickSearchQuery.initialSelection(
                from: results, currentItemID: nil, query: "")?.id,
            first.id
        )
        XCTAssertEqual(
            QuickSearchQuery.initialSelection(
                from: results, currentItemID: UUID(), query: "")?.id,
            first.id
        )
    }

    func testPromotingHistoryItemPreservesIdentityAndMovesItFirst() {
        let first = textItem("first")
        let selected = textItem("selected")
        let promotionDate = Date(timeIntervalSince1970: 1234)

        let result = ClipboardHistoryState.promoting(
            selected, in: [first, selected], at: promotionDate)

        XCTAssertEqual(result.item.id, selected.id)
        XCTAssertEqual(result.item.timestamp, promotionDate)
        XCTAssertEqual(result.history.map(\.id), [selected.id, first.id])
        XCTAssertEqual(result.history.count, 2)
    }

    func testRichHistoryItemContainsItsPlainTextRestore() {
        let textData = Data("restored text".utf8)
        let richItem = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [
                ClipboardContent(
                    data: textData,
                    formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                    description: "restored text"
                ),
                ClipboardContent(
                    data: Data("{\\rtf1 restored text}".utf8),
                    formats: [ClipboardFormat(uti: "public.rtf")],
                    description: "rich text"
                ),
            ],
            sourceApplication: nil
        )
        let plainTextCapture = [
            ClipboardContent(
                data: textData,
                formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
                description: "restored text"
            )
        ]

        XCTAssertTrue(richItem.containsRepresentations(from: plainTextCapture))
    }

    func testHistoryFilterFindsLateMatchInLargeText() {
        let lateNeedle = "LATE searchable phrase 🌍"
        let text = String(repeating: "a", count: 120_000) + lateNeedle
        let item = textItem(text)

        XCTAssertEqual(
            ClipboardHistoryFilter.matching([item], searchText: "late SEARCHABLE phrase 🌍").map(\.id),
            [item.id]
        )
        XCTAssertFalse(item.textRepresentation?.contains(lateNeedle) == true)
    }

    func testHistoryFilterFindsLateUTF16Match() {
        let text = String(repeating: "界", count: 120_000) + "最後の針"
        let content = ClipboardContent(
            data: text.data(using: .utf16)!,
            formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
            description: "UTF-16 text"
        )
        let item = ClipboardHistoryItem(
            timestamp: Date(), contents: [content], sourceApplication: nil)

        XCTAssertEqual(
            ClipboardHistoryFilter.matching([item], searchText: "最後の針").map(\.id),
            [item.id]
        )
    }

    func testHistoryFilterFindsASCIILateMatchInUTF16Text() {
        let text = String(repeating: "padding ", count: 20_000) + "ASCII LATE NEEDLE"
        let content = ClipboardContent(
            data: text.data(using: .utf16)!,
            formats: [ClipboardFormat(uti: "public.utf8-plain-text")],
            description: "UTF-16 ASCII text"
        )
        let item = ClipboardHistoryItem(
            timestamp: Date(), contents: [content], sourceApplication: nil)

        XCTAssertEqual(
            ClipboardHistoryFilter.matching([item], searchText: "ascii late needle").map(\.id),
            [item.id]
        )
    }

    func testSearchableTextCacheReusesDecodedValueAndCanBeCleared() {
        let content = textItem(String(repeating: "cached ", count: 20_000)).contents[0]
        let cache = ClipboardSearchTextCache(totalCostLimit: 1_000_000)

        XCTAssertNotNil(content.searchableText(cache: cache))
        XCTAssertNotNil(content.searchableText(cache: cache))
        XCTAssertEqual(cache.decodeCount(for: content), 1)

        cache.removeAll()
        XCTAssertNotNil(content.searchableText(cache: cache))
        XCTAssertEqual(cache.decodeCount(for: content), 1)
    }

    func testSingleFormatCopyWritesOnlyRequestedPasteboardType() {
        let pasteboard = NSPasteboard(name: .init("spaperclip-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let plain = ClipboardFormat(uti: "public.utf8-plain-text")
        let html = ClipboardFormat(uti: "public.html")
        let content = ClipboardContent(
            data: Data("same bytes".utf8),
            formats: [plain, html],
            description: "multi-format"
        )

        XCTAssertTrue(Utilities.copy(plain, from: content, to: pasteboard))
        XCTAssertTrue(pasteboard.types?.contains(NSPasteboard.PasteboardType(plain.uti)) == true)
        XCTAssertFalse(pasteboard.types?.contains(NSPasteboard.PasteboardType(html.uti)) == true)
        XCTAssertNil(pasteboard.data(forType: NSPasteboard.PasteboardType(html.uti)))
    }

    func testContentGroupCopyWritesEveryFormat() {
        let pasteboard = NSPasteboard(name: .init("spaperclip-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let formats = [
            ClipboardFormat(uti: "public.utf8-plain-text"),
            ClipboardFormat(uti: "public.html"),
        ]
        let content = ClipboardContent(
            data: Data("same bytes".utf8), formats: formats, description: "multi-format")

        XCTAssertTrue(Utilities.copy(content, to: pasteboard))
        XCTAssertNotNil(pasteboard.data(forType: NSPasteboard.PasteboardType(formats[0].uti)))
        XCTAssertNotNil(pasteboard.data(forType: NSPasteboard.PasteboardType(formats[1].uti)))
    }

    @MainActor
    func testLayoutAwareShortcutFindsPrintableCharacterKeyCode() {
        guard let keyCode = LayoutAwareShortcutManager.keyCode(for: "s") else {
            return XCTFail("Expected the active keyboard layout to contain s")
        }

        XCTAssertEqual(
            LayoutAwareShortcutManager.character(forKeyCode: keyCode).map {
                String($0).lowercased()
            },
            "s"
        )
    }

    func testLegacyImagePasteboardTypesHaveCompactLabels() {
        XCTAssertEqual(ClipboardFormat(uti: "NeXT TIFF v4.0 pasteboard type").shortTypeName, "TIFF")
        XCTAssertEqual(ClipboardFormat(uti: "Apple PNG pasteboard type").shortTypeName, "PNG")
    }

    func testImageHistoryPreviewIsLabeledAsImage() {
        let imageContent = ClipboardContent(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            formats: [ClipboardFormat(uti: "public.png")],
            description: "PNG image"
        )
        let item = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [imageContent],
            sourceApplication: nil
        )

        XCTAssertEqual(ClipboardHistoryPreview.fallbackText(for: item), "(Image)")
    }

    func testUnknownHistoryPreviewRemainsUnsupported() {
        let content = ClipboardContent(
            data: Data([0x00]),
            formats: [ClipboardFormat(uti: "com.example.unknown")],
            description: "Unknown"
        )
        let item = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [content],
            sourceApplication: nil
        )

        XCTAssertEqual(ClipboardHistoryPreview.fallbackText(for: item), "(Unsupported format)")
    }

    func testCopyAllContentTypesWritesToPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("spaperclip-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let item = textItem("restored clipboard value")

        XCTAssertTrue(Utilities.copyAllContentTypes(from: item, to: pasteboard))
        XCTAssertEqual(
            pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")),
            "restored clipboard value"
        )
    }

    func testCopyAllContentTypesRejectsEmptyItem() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("spaperclip-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let item = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [],
            sourceApplication: nil
        )

        XCTAssertTrue(pasteboard.setString("keep me", forType: .string))
        XCTAssertFalse(Utilities.copyAllContentTypes(from: item, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }

    func testPlainTextRestoreRejectsImageWithoutClearingPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("spaperclip-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.setString("keep me", forType: .string))
        let imageItem = ClipboardHistoryItem(
            timestamp: Date(),
            contents: [
                ClipboardContent(
                    data: Data([0x89, 0x50, 0x4E, 0x47]),
                    formats: [ClipboardFormat(uti: "public.png")],
                    description: "PNG image"
                )
            ],
            sourceApplication: nil
        )

        XCTAssertFalse(Utilities.copyPlainText(from: imageItem, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }
}
