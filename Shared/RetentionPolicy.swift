//
//  RetentionPolicy.swift
//  spaperclip
//
//  Defines how long clipboard items are kept before expiring.
//

import Foundation

/// Retention policy for clipboard items
enum RetentionPolicy: String, Codable, CaseIterable {
    case temporary = "7d"      // 7 days (default)
    case extended = "90d"      // 90 days
    case permanent = "forever" // Never expires

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .temporary: return "7 days"
        case .extended: return "90 days"
        case .permanent: return "Forever"
        }
    }

    /// Calculate expiration date from a given start date
    func expirationDate(from startDate: Date) -> Date? {
        switch self {
        case .temporary:
            return startDate.addingTimeInterval(7 * 24 * 60 * 60)
        case .extended:
            return startDate.addingTimeInterval(90 * 24 * 60 * 60)
        case .permanent:
            return nil
        }
    }
}
