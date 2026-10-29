import XCTest
import CoreData
@testable import FogOfWalk

final class LandmarkFixtureIsolationTests: XCTestCase {
    func testFixtureLaunchNeverConstructsProductionServices() async {
        await MainActor.run {
            var builds = 0
            let fixture = FogOfWalkApp.servicesForLaunch(arguments: ["-landmark-interaction-fixture"]) {
                builds += 1
                return "Production store and tracking"
            }
            XCTAssertNil(fixture)
            XCTAssertEqual(builds, 0)
            XCTAssertEqual(FogOfWalkApp.servicesForLaunch(arguments: []) { builds += 1; return 7 }, 7)
            XCTAssertEqual(builds, 1, "Normal and background launch still construct their services immediately")
        }
    }

    func testMemorySettingsAndLandmarkMigrationLeaveStandardDefaultsUntouched() async {
        await MainActor.run {
            let keys = ["com.fogofwalk.showLandmarks", "com.fogofwalk.highlightToday", LandmarkStore.wikidataMigrationKey]
            let before = keys.map { UserDefaults.standard.object(forKey: $0) as? NSNumber }
            let settings = GridSettings(defaults: nil)
            XCTAssertFalse(settings.showLandmarks)
            settings.showLandmarks = true
            settings.highlightToday = true
            let container = NSPersistentContainer(name: "FogOfWalk")
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
            container.loadPersistentStores { _, error in XCTAssertNil(error) }
            let store = LandmarkStore(container: container, defaults: nil)
            XCTAssertTrue(store.allLandmarks.isEmpty)
            XCTAssertEqual(keys.map { UserDefaults.standard.object(forKey: $0) as? NSNumber }, before)
            XCTAssertFalse(GridSettings(defaults: nil).showLandmarks)
        }
    }
}
