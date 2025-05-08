//
//  CDClipboardFormat+CoreDataProperties.swift
//  spaperclip
//
//  Created by Scott Opell on 5/8/25.
//
//

import Foundation
import CoreData


extension CDClipboardFormat {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDClipboardFormat> {
        return NSFetchRequest<CDClipboardFormat>(entityName: "CDClipboardFormat")
    }

    @NSManaged public var uti: String?
    @NSManaged public var content: CDClipboardContent?

}

extension CDClipboardFormat : Identifiable {

}
