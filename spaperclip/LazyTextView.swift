//
//  LazyTextView.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import Combine
import SwiftUI

/// A wrapper around NSTextView that efficiently handles large text content through lazy loading
struct LazyTextView: NSViewRepresentable {
    let content: ClipboardContent
    let isEditable: Bool

    // State to track loading status
    @State private var isLoading = false
    @State private var loadingProgress: Double = 0

    // Create an explicitly strong reference to prevent premature deallocation
    class TextLoadingCoordinator: NSObject {
        var textLoadingTask: DispatchWorkItem?
        var isLoadingCancelled = false

        deinit {
            cancelLoading()
        }

        func cancelLoading() {
            isLoadingCancelled = true
            textLoadingTask?.cancel()
            textLoadingTask = nil
        }
    }

    // Store the loading coordinator
    @State private var textLoadingCoordinator = TextLoadingCoordinator()

    // Function to make the NSView
    func makeNSView(context: Context) -> NSScrollView {
        // Create scrollable text view
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        // Configure the text view
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = NSColor.textBackgroundColor

        // Use a layout manager that's optimized for large text
        textView.layoutManager?.allowsNonContiguousLayout = true

        // Set delegate for scroll detection and lazy loading
        textView.delegate = context.coordinator

        // Start loading content asynchronously
        startTextLoading(textView: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Ensure delegate is properly set for the text view
        if let textView = nsView.documentView as? NSTextView {
            textView.delegate = context.coordinator
        }

        // If content has changed, reload the text
        if context.coordinator.currentContentID != content.id {
            context.coordinator.currentContentID = content.id
            textLoadingCoordinator.cancelLoading()

            if let textView = nsView.documentView as? NSTextView {
                startTextLoading(textView: textView)
            }
        }
    }

    // Create a coordinator to handle text view delegate methods
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // Start loading the text content
    private func startTextLoading(textView: NSTextView) {
        // Cancel any previous loading
        textLoadingCoordinator.cancelLoading()

        // Reset loading state
        textLoadingCoordinator.isLoadingCancelled = false

        // Create a new loading task
        let loadingTask = DispatchWorkItem { [textLoadingCoordinator] in
            // Guard against cancellation
            if textLoadingCoordinator.isLoadingCancelled { return }

            loadTextContent(
                textView: textView, content: content, coordinator: textLoadingCoordinator)
        }

        textLoadingCoordinator.textLoadingTask = loadingTask

        // Show loading indicator in the main thread
        DispatchQueue.main.async {
            textView.string = "Loading content..."
        }

        // Start the loading task
        DispatchQueue.global(qos: .userInitiated).async(execute: loadingTask)
    }

    // Load text content in chunks
    private func loadTextContent(
        textView: NSTextView, content: ClipboardContent, coordinator: TextLoadingCoordinator
    ) {
        // Get approximate size of the content
        let estimatedSize = content.getTextSize() ?? 0

        // For small content, load it all at once
        if estimatedSize < 100_000 {
            if let text = content.getTextRepresentation() {
                // Check for cancellation before updating UI
                if coordinator.isLoadingCancelled { return }

                DispatchQueue.main.async {
                    // Check for cancellation again before updating UI
                    if coordinator.isLoadingCancelled { return }
                    textView.string = text
                }
            }
            return
        }

        // For large content, load in chunks
        let chunkSize = 50_000  // Characters per chunk
        var offset = 0

        // Initial chunk
        if let chunkResult = content.getTextChunk(offset: 0, length: chunkSize) {
            // Update the offset for next chunk
            offset = chunkResult.nextOffset

            // Check for cancellation
            if coordinator.isLoadingCancelled { return }

            DispatchQueue.main.async {
                // Check for cancellation
                if coordinator.isLoadingCancelled { return }

                textView.string = chunkResult.text

                // Add a loading indicator
                if estimatedSize > chunkSize {
                    let loadingText =
                        "\n\n[Loading... \(Int((Double(offset) / Double(estimatedSize)) * 100))% of ~\(Utilities.formatSize(estimatedSize)) characters]"
                    textView.string += loadingText
                }
            }
        }

        // Continue loading chunks in the background
        // Only continue if needed
        if estimatedSize <= chunkSize {
            return
        }

        // Background loading of subsequent chunks
        while offset < estimatedSize && !coordinator.isLoadingCancelled {
            let chunkLength = min(chunkSize, estimatedSize - offset)
            if let chunkResult = content.getTextChunk(offset: offset, length: chunkLength) {
                // Update the offset for next chunk
                let nextOffset = chunkResult.nextOffset

                // Check for cancellation
                if coordinator.isLoadingCancelled { return }

                DispatchQueue.main.async {
                    // Check for cancellation
                    if coordinator.isLoadingCancelled { return }

                    // Get the current text without the loading indicator
                    var currentText = textView.string
                    if let loadingRange = currentText.range(of: "\n\n[Loading...") {
                        currentText = String(currentText[..<loadingRange.lowerBound])
                    }

                    // Append the new chunk
                    let newText = currentText + chunkResult.text

                    // Calculate progress
                    let progress =
                        Double(min(nextOffset, estimatedSize)) / Double(estimatedSize)

                    // Update text with progress indicator if not complete
                    if nextOffset < estimatedSize {
                        let updatedText =
                            newText
                            + "\n\n[Loading... \(Int(progress * 100))% of ~\(Utilities.formatSize(estimatedSize)) characters]"
                        textView.string = updatedText
                    } else {
                        textView.string = newText
                    }
                }

                // Move to next chunk
                offset = nextOffset
            } else {
                // If we couldn't get the next chunk, break the loop
                break
            }

            // Small delay to prevent UI blocking
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    // Coordinator class for delegate methods
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LazyTextView
        var currentContentID: UUID? = nil

        init(_ parent: LazyTextView) {
            self.parent = parent
        }

        // Add delegate methods if needed for scroll detection
        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
            toCharacterRange newSelectedCharRange: NSRange
        ) -> NSRange {
            return newSelectedCharRange
        }
    }
}
