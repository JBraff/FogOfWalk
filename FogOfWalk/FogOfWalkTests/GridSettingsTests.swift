import XCTest
@testable import FogOfWalk

// All tests are `async` and work inside `MainActor.run` — see the header of
// ExplorationStoreTests.swift for the iOS 26+ simulator dealloc crash this avoids.
final class GridSettingsTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let name = "fog-grid-settings-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    func testEarlierHighlightSettingBecomesNewToday() async {
        await MainActor.run {
            for (legacy, expected) in [(true, TodayHighlight.newToday), (false, .off)] {
                let defaults = makeDefaults()
                defaults.set(legacy, forKey: "com.fogofwalk.highlightToday")
                XCTAssertEqual(GridSettings(defaults: defaults).todayHighlight, expected)
            }
            XCTAssertEqual(GridSettings(defaults: makeDefaults()).todayHighlight, .off)
        }
    }

    func testTodayHighlightPersistsAndOverridesTheEarlierSetting() async {
        await MainActor.run {
            let defaults = makeDefaults()
            defaults.set(true, forKey: "com.fogofwalk.highlightToday")
            let settings = GridSettings(defaults: defaults)
            settings.todayHighlight = .walkedToday
            XCTAssertEqual(GridSettings(defaults: defaults).todayHighlight, .walkedToday)
            settings.todayHighlight = .off
            XCTAssertEqual(GridSettings(defaults: defaults).todayHighlight, .off)
            XCTAssertNil(settings.highlightCutoffDate)
        }
    }

    func testTapCyclesOffNewWalked() async {
        await MainActor.run {
            XCTAssertEqual(TodayHighlight.off.next, .newToday)
            XCTAssertEqual(TodayHighlight.newToday.next, .walkedToday)
            XCTAssertEqual(TodayHighlight.walkedToday.next, .off)
            XCTAssertEqual(TodayHighlight.newToday.basis, .firstVisited)
            XCTAssertEqual(TodayHighlight.walkedToday.basis, .lastVisited)
        }
    }
}
