//
//  CDClipboardContent+CoreDataProperties.swift
//  spaperclip
//
//  Created by Scott Opell on 5/8/25.
//
//

import Foundation
import CoreData


extension CDClipboardContent {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDClipboardContent> {
        return NSFetchRequest<CDClipboardContent>(entityName: "CDClipboardContent")
    }

    @NSManaged public var data: Data?
    @NSManaged public var descriptionText: String?
    @NSManaged public var formats: NSSet?
    @NSManaged public var historyItem: CDClipboardHistoryItem?

}

// MARK: Generated accessors for formats
extension CDClipboardContent {

    @objc(addFormatsObject:)
    @NSManaged public func addToFormats(_ value: CDClipboardFormat)

    @objc(removeFormatsObject:)
    @NSManaged public func removeFromFormats(_ value: CDClipboardFormat)

    @objc(addFormats:)
    @NSManaged public func addToFormats(_ values: NSSet)

    @objc(removeFormats:)
    @NSManaged public func removeFromFormats(_ values: NSSet)

}

extension CDClipboardContent : Identifiable {

}
