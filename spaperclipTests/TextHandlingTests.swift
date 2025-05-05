//
//  TextHandlingTests.swift
//  spaperclipTests
//
//  Created by Scott Opell on 5/4/25.
//

import UniformTypeIdentifiers
import XCTest

@testable import spaperclip

final class TextHandlingTests: XCTestCase {

    // Test basic chunking with simple ASCII text
    func testBasicTextChunking() {
        // Create test text with 1000 characters
        let testText = String(repeating: "abcdefghij", count: 100)
        let data = testText.data(using: .utf8)!

        // Create clipboard content
        let format = ClipboardFormat(uti: UTType.plainText.identifier)
        let content = ClipboardContent(data: data, formats: [format], description: "Test Text")

        // Test getting chunks
        if let (chunk1, nextOffset1) = content.getTextChunk(offset: 0, length: 100) {
            XCTAssertEqual(chunk1.count, 100)
            XCTAssertEqual(nextOffset1, 100)
            XCTAssertEqual(chunk1, String(testText.prefix(100)))

            // Get next chunk
            if let (chunk2, nextOffset2) = content.getTextChunk(offset: nextOffset1, length: 150) {
                XCTAssertEqual(chunk2.count, 150)
                XCTAssertEqual(nextOffset2, 250)

                // Verify the chunk contents
                let expectedStart = testText.index(testText.startIndex, offsetBy: 100)
                let expectedEnd = testText.index(testText.startIndex, offsetBy: 250)
                XCTAssertEqual(chunk2, String(testText[expectedStart..<expectedEnd]))
            } else {
                XCTFail("Failed to get second chunk")
            }
        } else {
            XCTFail("Failed to get first chunk")
        }
    }

    // Test chunking with multi-byte UTF-8 characters
    func testMultiByteTextChunking() {
        // Create test text with multi-byte characters (emoji and special chars)
        let multiByteText = "Hello 🌍 World! こんにちは 世界! Здравствуй мир! 👋👨‍👩‍👧‍👦"
        let repeatedText = String(repeating: multiByteText, count: 20)
        let data = repeatedText.data(using: .utf8)!

        // Create clipboard content
        let format = ClipboardFormat(uti: UTType.plainText.identifier)
        let content = ClipboardContent(
            data: data, formats: [format], description: "Multi-byte Text")

        // Test getting chunks with various lengths
        if let (chunk1, nextOffset1) = content.getTextChunk(offset: 0, length: 10) {
            XCTAssertEqual(chunk1.count, 10)
            XCTAssertEqual(nextOffset1, 10)

            // Get next chunk
            if let (chunk2, nextOffset2) = content.getTextChunk(offset: nextOffset1, length: 15) {
                XCTAssertEqual(chunk2.count, 15)
                XCTAssertEqual(nextOffset2, 25)

                // Verify we can concatenate the chunks without issues
                let combined = chunk1 + chunk2
                let expectedStart = repeatedText.startIndex
                let expectedEnd = repeatedText.index(expectedStart, offsetBy: 25)
                XCTAssertEqual(combined, String(repeatedText[expectedStart..<expectedEnd]))
            } else {
                XCTFail("Failed to get second chunk")
            }
        } else {
            XCTFail("Failed to get first chunk")
        }
    }

    // Test handling of extremely large texts
    func testLargeTextHandling() {
        // Create large text (over 100KB)
        let singleLine = String(repeating: "abcdefghij", count: 1000)  // 10,000 characters
        let largeText = String(repeating: singleLine + "\n", count: 12)  // ~120,000 characters
        let data = largeText.data(using: .utf8)!

        // Create clipboard content
        let format = ClipboardFormat(uti: UTType.plainText.identifier)
        let content = ClipboardContent(data: data, formats: [format], description: "Large Text")

        // Test getting chunks of various sizes
        if let (chunk1, nextOffset1) = content.getTextChunk(offset: 0, length: 5000) {
            XCTAssertEqual(chunk1.count, 5000)
            XCTAssertEqual(nextOffset1, 5000)

            // Get chunk from middle
            if let (chunk2, nextOffset2) = content.getTextChunk(offset: 50000, length: 10000) {
                XCTAssertEqual(chunk2.count, 10000)
                XCTAssertEqual(nextOffset2, 60000)

                // Verify the chunk contents
                let expectedStart = largeText.index(largeText.startIndex, offsetBy: 50000)
                let expectedEnd = largeText.index(largeText.startIndex, offsetBy: 60000)
                XCTAssertEqual(chunk2, String(largeText[expectedStart..<expectedEnd]))
            } else {
                XCTFail("Failed to get middle chunk")
            }

            // Get chunk near the end
            let endOffset = largeText.count - 1000
            if let (endChunk, finalOffset) = content.getTextChunk(offset: endOffset, length: 2000) {
                // We expect the chunk to be truncated
                XCTAssertEqual(finalOffset, largeText.count)
                XCTAssertEqual(endChunk.count, 1000)

                // Verify the chunk contents
                let expectedStart = largeText.index(largeText.startIndex, offsetBy: endOffset)
                XCTAssertEqual(endChunk, String(largeText[expectedStart...]))
            } else {
                XCTFail("Failed to get end chunk")
            }
        } else {
            XCTFail("Failed to get first chunk")
        }
    }

    // Test character boundary correctness - specifically test that we don't split multi-byte characters
    func testCharacterBoundaryHandling() {
        // Create text with emoji and other multi-byte characters that we'll attempt to split
        let emoji = "👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦"  // Each family emoji is multiple code points
        let repeatedEmoji = String(repeating: emoji, count: 100)
        let data = repeatedEmoji.data(using: .utf8)!

        // Create clipboard content
        let format = ClipboardFormat(uti: UTType.plainText.identifier)
        let content = ClipboardContent(data: data, formats: [format], description: "Emoji Text")

        // Test getting chunks of varying sizes to ensure we don't split characters
        for chunkSize in [1, 2, 3, 5, 7, 10, 13] {
            var offset = 0
            var allChunks = ""

            // Collect all chunks
            while offset < repeatedEmoji.count {
                if let (chunk, nextOffset) = content.getTextChunk(offset: offset, length: chunkSize)
                {
                    // The chunk should have valid UTF-8
                    XCTAssertGreaterThan(chunk.utf8.count, 0, "Chunk should have valid UTF-8")

                    // The next offset should always be greater than the current offset
                    XCTAssertGreaterThan(
                        nextOffset, offset, "Next offset should be greater than current offset")

                    // Add to our accumulated text
                    allChunks += chunk
                    offset = nextOffset
                } else {
                    XCTFail("Failed to get chunk at offset \(offset)")
                    break
                }
            }

            // The concatenated chunks should exactly match the original text
            XCTAssertEqual(
                allChunks, repeatedEmoji, "Concatenated chunks should match original text")
        }
    }
}
