import AppKit
import Foundation
import SwiftUI

/// Contains common utility functions used throughout the application
enum Utilities {

    /// Formats a date with a standard timestamp format
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Formats a size in bytes or characters with appropriate units (K, M)
    static func formatSize(_ size: Int) -> String {
        if size < 1_000 {
            return "\(size)"
        } else if size < 1_000_000 {
            return String(format: "%.1fK", Double(size) / 1_000)
        } else {
            return String(format: "%.1fM", Double(size) / 1_000_000)
        }
    }

    /// Truncates a string to a maximum length and adds an ellipsis if needed
    static func truncateString(_ str: String, maxLength: Int = 100) -> String {
        if str.count > maxLength {
            return String(str.prefix(maxLength)) + "..."
        }
        return str
    }

    /// Copies all content types from a clipboard history item to the system clipboard
    static func copyAllContentTypes(from item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for content in item.contents {
            for format in content.formats {
                pasteboard.setData(content.data, forType: NSPasteboard.PasteboardType(format.uti))
            }
        }
    }

    static func copyToClipboard(_ content: ClipboardContent) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for format in content.formats {
            pasteboard.setData(content.data, forType: NSPasteboard.PasteboardType(format.uti))
        }
    }
}

// MARK: - String Extensions

extension String {
    /// Truncates the string to a maximum length and adds ellipsis if needed
    func truncated(to maxLength: Int = 100) -> String {
        return Utilities.truncateString(self, maxLength: maxLength)
    }
}
