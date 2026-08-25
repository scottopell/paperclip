//
//  ClipboardMonitorDuplicateTests.swift
//  spaperclipTests
//

import UniformTypeIdentifiers
import XCTest
@testable import spaperclip

@MainActor
final class ClipboardMonitorDuplicateTests: XCTestCase {
    private func makeContent(
        text: String,
        formats: [String] = [UTType.plainText.identifier]
    ) -> ClipboardContent {
        ClipboardContent(
            data: text.data(using: .utf8)!,
            formats: formats.map(ClipboardFormat.init(uti:)),
            description: text
        )
    }

    private func makeItem(
        contents: [ClipboardContent],
        source: SourceApplicationInfo? = nil
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            timestamp: Date(),
            contents: contents,
            sourceApplication: source
        )
    }

    func testClipboardFormatUsesStableViewIdentityAndSemanticEquality() {
        let a = ClipboardFormat(uti: UTType.plainText.identifier)
        let b = ClipboardFormat(uti: UTType.plainText.identifier)

        XCTAssertNotEqual(a.id, b.id, "separate views keep separate identities")
        XCTAssertEqual(a, b, "formats with the same UTI are semantically equal")
        XCTAssertEqual(a.hashValue, b.hashValue, "equal formats must hash equally")
    }

    func testDuplicateReCopyUsesProductionPathAndKeepsCurrentIndicatorOnTopItem() {
        let monitor = ClipboardMonitor(loadPersistedHistory: false)
        let first = makeItem(contents: [makeContent(text: "hello")])
        let duplicate = makeItem(contents: [makeContent(text: "hello")])

        monitor.applyHistoryItem(first, persist: false)
        monitor.applyHistoryItem(duplicate, persist: false)

        XCTAssertEqual(monitor.history.count, 1, "duplicate payload should reuse one row")
        XCTAssertEqual(monitor.history.first?.id, first.id, "existing row should move to the top")
        XCTAssertEqual(monitor.selectedHistoryItem?.id, first.id)
        XCTAssertEqual(monitor.currentItem?.id, first.id)
        XCTAssertEqual(monitor.currentItemID, first.id)
    }

    func testDuplicateDetectionIgnoresContentAndFormatOrdering() {
        let monitor = ClipboardMonitor(loadPersistedHistory: false)
        let text = makeContent(
            text: "hello",
            formats: [UTType.plainText.identifier, UTType.utf8PlainText.identifier]
        )
        let image = ClipboardContent(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            formats: [ClipboardFormat(uti: UTType.png.identifier)],
            description: "Binary data (4 bytes)"
        )
        let first = makeItem(contents: [text, image])
        let reorderedText = makeContent(
            text: "hello",
            formats: [UTType.utf8PlainText.identifier, UTType.plainText.identifier]
        )
        let duplicate = makeItem(contents: [image, reorderedText])

        monitor.applyHistoryItem(first, persist: false)
        monitor.applyHistoryItem(duplicate, persist: false)

        XCTAssertEqual(monitor.history.count, 1)
        XCTAssertEqual(monitor.currentItemID, first.id)
    }

    func testDuplicateCaptureKeepsOriginalSourceAttribution() {
        let monitor = ClipboardMonitor(loadPersistedHistory: false)
        let content = makeContent(text: "hello")
        let safari = SourceApplicationInfo(bundleIdentifier: "com.apple.Safari", applicationName: "Safari")
        let notes = SourceApplicationInfo(bundleIdentifier: "com.apple.Notes", applicationName: "Notes")
        let first = makeItem(contents: [content], source: safari)
        let duplicate = makeItem(contents: [content], source: notes)

        monitor.applyHistoryItem(first, persist: false)
        monitor.applyHistoryItem(duplicate, persist: false)

        XCTAssertEqual(monitor.history.count, 1)
        XCTAssertEqual(monitor.history.first?.id, first.id)
        XCTAssertEqual(monitor.history.first?.sourceApplication, safari)
        XCTAssertEqual(monitor.history.first?.timestamp, duplicate.timestamp)
    }
}
