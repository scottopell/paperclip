//
//  CDSourceApplicationInfo+CoreDataProperties.swift
//  spaperclip
//
//  Created by Scott Opell on 5/8/25.
//
//

import Foundation
import CoreData


extension CDSourceApplicationInfo {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSourceApplicationInfo> {
        return NSFetchRequest<CDSourceApplicationInfo>(entityName: "CDSourceApplicationInfo")
    }

    @NSManaged public var applicationIconData: Data?
    @NSManaged public var applicationName: String?
    @NSManaged public var bundleIdentifier: String?
    @NSManaged public var historyItems: NSSet?

}

// MARK: Generated accessors for historyItems
extension CDSourceApplicationInfo {

    @objc(addHistoryItemsObject:)
    @NSManaged public func addToHistoryItems(_ value: CDClipboardHistoryItem)

    @objc(removeHistoryItemsObject:)
    @NSManaged public func removeFromHistoryItems(_ value: CDClipboardHistoryItem)

    @objc(addHistoryItems:)
    @NSManaged public func addToHistoryItems(_ values: NSSet)

    @objc(removeHistoryItems:)
    @NSManaged public func removeFromHistoryItems(_ values: NSSet)

}

extension CDSourceApplicationInfo : Identifiable {

}
