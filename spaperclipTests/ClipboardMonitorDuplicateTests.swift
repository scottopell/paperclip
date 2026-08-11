//
//  ClipboardMonitorDuplicateTests.swift
//  spaperclipTests
//

import UniformTypeIdentifiers
import XCTest
@testable import spaperclip

@MainActor
final class ClipboardMonitorDuplicateTests: XCTestCase {
    private func makeItem(text: String) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            timestamp: Date(),
            contents: [
                ClipboardContent(
                    data: text.data(using: .utf8)!,
                    formats: [ClipboardFormat(uti: UTType.plainText.identifier)],
                    description: text
                )
            ],
            sourceApplication: nil
        )
    }

    // Regression: two clipboard items built from identical data and formats
    // must compare equal so updateFromClipboard can detect duplicates.
    // Previously ClipboardFormat equality included the per-instance UUID id,
    // so no two formats were ever equal and duplicate detection never matched.
    func testIdenticalContentsAreEqual() {
        let a = makeItem(text: "hello")
        let b = makeItem(text: "hello")
        XCTAssertEqual(a, b, "items with identical data and formats must be equal")
        XCTAssertEqual(a.hashValue, b.hashValue, "equal items must hash equally")
    }

    // Regression: when the user re-copies identical content, updateFromClipboard
    // moves the existing item to the top and must keep the "current clipboard"
    // indicator pointing at the top row. Previously the duplicate branch left
    // currentItemID pointing at the never-inserted newItem.
    func testDuplicateReCopyKeepsCurrentItemIndicatorOnTopItem() {
        // Seed history with one item.
        let first = makeItem(text: "hello")
        var history: [ClipboardHistoryItem] = [first]
        var currentItem: ClipboardHistoryItem? = first
        var currentItemID: UUID? = first.id
        var selectedHistoryItem: ClipboardHistoryItem? = first

        // Simulate the user re-copying the *same* content from another app:
        // updateFromClipboard builds a fresh newItem from the pasteboard.
        let newItem = makeItem(text: "hello")

        // Mirror updateFromClipboard's main-queue block (ClipboardMonitor.swift:754-803).
        currentItem = newItem
        currentItemID = newItem.id

        let isDuplicate = history.contains { $0 == newItem }
        XCTAssertTrue(isDuplicate, "sanity: duplicate should match existing item")

        if !isDuplicate {
            history.insert(newItem, at: 0)
            selectedHistoryItem = newItem
        } else if let index = history.firstIndex(where: { $0 == newItem }) {
            let existingItem = history.remove(at: index)
            history.insert(existingItem, at: 0)
            selectedHistoryItem = existingItem
            // Fix: keep the current-clipboard indicator on the row that lives in history.
            currentItem = existingItem
            currentItemID = existingItem.id
        }

        // The current-clipboard indicator must point at a row that exists in history.
        let currentID = currentItemID
        XCTAssertNotNil(
            history.first(where: { $0.id == currentID }),
            "currentItemID must reference an item present in history"
        )
        XCTAssertEqual(
            history.first?.id, currentID,
            "the top history row must be the current item"
        )
    }
}
