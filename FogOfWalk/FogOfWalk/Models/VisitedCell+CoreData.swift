import CoreData

@objc(VisitedCell)
public class VisitedCell: NSManagedObject {
    @NSManaged public var cellX:          Int32
    @NSManaged public var cellY:          Int32
    @NSManaged public var cellSizeMeters: Double
    @NSManaged public var firstVisited:   Date?
    @NSManaged public var locality:       String?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<VisitedCell> {
        NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
    }
}
