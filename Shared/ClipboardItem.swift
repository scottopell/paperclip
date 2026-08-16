//
//  ClipboardItem.swift
//  spaperclip
//
//  SwiftData model for clipboard history items.
//  Shared between macOS and iOS apps.
//

import Foundation
import SwiftData

@Model
final class ClipboardItem {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// The text content (primary content type for now)
    var text: String?

    /// When this item was captured
    var timestamp: Date

    /// Retention policy as raw string (for SwiftData compatibility)
    var retentionPolicyRaw: String

    /// When this item expires (nil = never)
    var expirationDate: Date?

    // MARK: - Computed Properties

    /// Retention policy (computed from raw string)
    var retentionPolicy: RetentionPolicy {
        get { RetentionPolicy(rawValue: retentionPolicyRaw) ?? .temporary }
        set {
            retentionPolicyRaw = newValue.rawValue
            expirationDate = newValue.expirationDate(from: timestamp)
        }
    }

    /// Whether this item has expired
    var isExpired: Bool {
        guard let expiration = expirationDate else { return false }
        return Date() > expiration
    }

    /// Preview text for display in lists
    var previewText: String {
        guard let text = text else { return "(No text content)" }
        if text.count > 100 {
            return String(text.prefix(100)) + "..."
        }
        return text
    }

    // MARK: - Initialization

    init(text: String?, retentionPolicy: RetentionPolicy = .temporary) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.retentionPolicyRaw = retentionPolicy.rawValue
        self.expirationDate = retentionPolicy.expirationDate(from: Date())
    }
}
