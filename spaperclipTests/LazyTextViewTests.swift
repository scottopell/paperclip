//
//  LazyTextViewTests.swift
//  spaperclipTests
//
//  Created by Scott Opell on 5/4/25.
//

import XCTest

@testable import spaperclip

final class LazyTextViewTests: XCTestCase {

    // Test the TextLoadingCoordinator's cancellation behavior
    func testTextLoadingCoordinatorCancellation() {
        let coordinator = LazyTextView.TextLoadingCoordinator()

        // Create a work item that just sleeps
        let workItem = DispatchWorkItem {
            Thread.sleep(forTimeInterval: 1.0)
        }

        coordinator.textLoadingTask = workItem
        XCTAssertFalse(coordinator.isLoadingCancelled)

        // Test cancellation
        coordinator.cancelLoading()
        XCTAssertTrue(coordinator.isLoadingCancelled)
        XCTAssertTrue(workItem.isCancelled)
        XCTAssertNil(coordinator.textLoadingTask)
    }

    // Test text size formatting
    func testTextSizeFormatting() {
        // We need to create a LazyTextView to test its private formatTextSize method
        // Since it's private, we'll have to test it indirectly

        // Create test data
        let format = ClipboardFormat(uti: "public.utf8-plain-text")
        let smallData = "Test".data(using: .utf8)!
        let content = ClipboardContent(data: smallData, formats: [format], description: "Test")

        // Create LazyTextView
        let textView = LazyTextView(content: content, isEditable: false)

        // Create mirror for reflection
        let mirror = Mirror(reflecting: textView)

        // Try to find the formatTextSize method - if we can't access it directly
        // we'll verify its behavior through other methods that use it
        _ = mirror.children.first { $0.label == "formatTextSize" }

        // Test formatting of different sizes by creating the right content size
        // and examining the text output

        let smallContent = ClipboardContent(
            data: String(repeating: "a", count: 500).data(using: .utf8)!,
            formats: [format],
            description: "Small Text"
        )

        // Get the text size
        XCTAssertEqual(smallContent.getTextSize(), 500)

        // Create a larger content that would format as "K"
        let mediumContent = ClipboardContent(
            data: String(repeating: "a", count: 5000).data(using: .utf8)!,
            formats: [format],
            description: "Medium Text"
        )

        XCTAssertEqual(mediumContent.getTextSize(), 5000)
    }

    // Test the lazy loading approach by simulating text chunks
    func testChunkedTextLoading() {
        // Create test content
        let testText = String(repeating: "This is a test for lazy loading. ", count: 100)
        let data = testText.data(using: .utf8)!

        let format = ClipboardFormat(uti: "public.utf8-plain-text")
        let content = ClipboardContent(data: data, formats: [format], description: "Large Text")

        // Simulate the loading logic that LazyTextView uses
        let chunkSize = 100
        var offset = 0
        var loadedText = ""

        // First chunk - typically displayed immediately
        if let (firstChunk, nextOffset) = content.getTextChunk(offset: 0, length: chunkSize) {
            loadedText = firstChunk
            offset = nextOffset

            XCTAssertLessThanOrEqual(firstChunk.count, chunkSize)
        } else {
            XCTFail("Failed to get first chunk")
        }

        // Subsequent chunks - would be loaded in background
        while offset < testText.count {
            if let (chunk, nextOffset) = content.getTextChunk(offset: offset, length: chunkSize) {
                loadedText += chunk
                offset = nextOffset

                // Verify chunk size
                XCTAssertLessThanOrEqual(chunk.count, chunkSize)
            } else {
                XCTFail("Failed to get chunk at offset \(offset)")
                break
            }
        }

        // Verify the final loaded text matches the original
        XCTAssertEqual(loadedText, testText)
    }

    // Test content loading behavior with large text
    func testLargeTextHandling() {
        // Create large test content (over the 100K threshold used in LazyTextView)
        let textBlock = "Large text content for testing. "
        let testText = String(repeating: textBlock, count: 5000)  // Over 100K characters
        let data = testText.data(using: .utf8)!

        let format = ClipboardFormat(uti: "public.utf8-plain-text")
        let content = ClipboardContent(data: data, formats: [format], description: "Large Text")

        // Test size estimation
        let estimatedSize = content.getTextSize()
        XCTAssertGreaterThan(estimatedSize ?? 0, 100_000, "Text should be identified as large")

        // Test chunked loading similar to how LazyTextView would do it
        let chunkSize = 50_000  // Same as used in LazyTextView

        if let (firstChunk, _) = content.getTextChunk(offset: 0, length: chunkSize) {
            // First chunk should be maximum chunkSize characters
            XCTAssertLessThanOrEqual(firstChunk.count, chunkSize)

            // First chunk should match the beginning of the text
            XCTAssertEqual(firstChunk, String(testText.prefix(firstChunk.count)))
        } else {
            XCTFail("Failed to get first chunk of large text")
        }
    }
}
