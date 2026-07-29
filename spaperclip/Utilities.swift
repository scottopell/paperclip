import AppKit
import Foundation
import SwiftUI

/// Contains common utility functions used throughout the application
enum Utilities {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, h:mm a"
        return formatter
    }()
    private static let recentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    /// Formats a date with a standard timestamp format
    static func formatDate(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static func formatRelativeDate(
        _ date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return "Just now" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60)) min ago" }
        if calendar.isDate(date, inSameDayAs: now) {
            let hours = Int(elapsed / 3_600)
            return "\(hours) hr\(hours == 1 ? "" : "s") ago"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday, \(timeFormatter.string(from: date))"
        }
        if let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: now),
            date >= sixDaysAgo
        {
            return weekdayFormatter.string(from: date)
        }
        return recentDateFormatter.string(from: date)
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

    /// Copies all content types from a clipboard history item to a pasteboard.
    @discardableResult
    static func copyAllContentTypes(
        from item: ClipboardHistoryItem,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard item.contents.contains(where: { !$0.formats.isEmpty }) else { return false }
        pasteboard.clearContents()

        var copiedAnyContent = false
        for content in item.contents {
            for format in content.formats {
                copiedAnyContent = pasteboard.setData(
                    content.data,
                    forType: NSPasteboard.PasteboardType(format.uti)
                ) || copiedAnyContent
            }
        }
        return copiedAnyContent
    }

    @discardableResult
    static func copyPlainText(
        from item: ClipboardHistoryItem,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let text = item.textRepresentation else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    static func copyToClipboard(
        _ content: ClipboardContent,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard !content.formats.isEmpty else { return false }
        pasteboard.clearContents()

        var copiedAnyContent = false
        for format in content.formats {
            copiedAnyContent = pasteboard.setData(
                content.data,
                forType: NSPasteboard.PasteboardType(format.uti)
            ) || copiedAnyContent
        }
        return copiedAnyContent
    }
}

// MARK: - String Extensions

extension String {
    /// Truncates the string to a maximum length and adds ellipsis if needed
    func truncated(to maxLength: Int = 100) -> String {
        return Utilities.truncateString(self, maxLength: maxLength)
    }
}
