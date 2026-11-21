import CoreData

@objc(VisitedCell)
public class VisitedCell: NSManagedObject {
    @NSManaged public var cellX:          Int32
    @NSManaged public var cellY:          Int32
    @NSManaged public var cellSizeMeters: Double
    @NSManaged public var firstVisited:   Date?
    /// When the cell was last walked: set on the first sample in it each local day.
    @NSManaged public var lastVisited:    Date?
    /// Distinct local calendar days the cell was walked, including the first.
    @NSManaged public var daysVisited:    Int32
    @NSManaged public var locality:       String?
    @NSManaged public var state:          String?
    @NSManaged public var country:        String?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<VisitedCell> {
        NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
    }
}
