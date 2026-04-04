import CoreData

@objc(Landmark)
public class Landmark: NSManagedObject {
    @NSManaged public var identifier:            String
    @NSManaged public var name:                  String
    @NSManaged public var category:              String
    @NSManaged public var latitude:              Double
    @NSManaged public var longitude:             Double
    @NSManaged public var discoveryRadiusMeters: Double
    @NSManaged public var isDiscovered:          Bool
    @NSManaged public var firstDiscovered:       Date?
    @NSManaged public var firstSeen:             Date

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Landmark> {
        NSFetchRequest<Landmark>(entityName: "Landmark")
    }
}
