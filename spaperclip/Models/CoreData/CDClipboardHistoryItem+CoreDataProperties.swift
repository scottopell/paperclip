//
//  CDClipboardHistoryItem+CoreDataProperties.swift
//  spaperclip
//
//  Created by Scott Opell on 5/8/25.
//
//

import CoreData
import Foundation

extension CDClipboardHistoryItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDClipboardHistoryItem> {
        return NSFetchRequest<CDClipboardHistoryItem>(entityName: "CDClipboardHistoryItem")
    }

    @NSManaged public var timestamp: Date?
    @NSManaged public var contents: NSSet?
    @NSManaged public var sourceApplication: CDSourceApplicationInfo?

}

// MARK: Generated accessors for contents
extension CDClipboardHistoryItem {

    @objc(addContentsObject:)
    @NSManaged public func addToContents(_ value: CDClipboardContent)

    @objc(removeContentsObject:)
    @NSManaged public func removeFromContents(_ value: CDClipboardContent)

    @objc(addContents:)
    @NSManaged public func addToContents(_ values: NSSet)

    @objc(removeContents:)
    @NSManaged public func removeFromContents(_ values: NSSet)

}

extension CDClipboardHistoryItem: Identifiable {

}
