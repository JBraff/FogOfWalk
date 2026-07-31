import CoreData

@objc(VisitedCell)
public class VisitedCell: NSManagedObject {
    @NSManaged public var cellX:          Int32
    @NSManaged public var cellY:          Int32
    @NSManaged public var cellSizeMeters: Double
    @NSManaged public var firstVisited:   Date?
    @NSManaged public var locality:       String?
    @NSManaged public var state:          String?
    @NSManaged public var country:        String?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<VisitedCell> {
        NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
    }
}
