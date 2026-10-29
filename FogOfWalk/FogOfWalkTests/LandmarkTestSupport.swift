import XCTest
import MapKit

struct LandmarkUIWaitTimeout: Error, CustomStringConvertible {
    let description: String
}

/// Deadline-bounded polling that yields to UIKit/MapKit between checks. There is no
/// separate waiter, so nothing can fulfill after the wait ends, and a timeout fails
/// at the deadline with the condition's description. Sleeping releases the main actor.
@MainActor
func waitForLandmarkUI(_ description: String, timeout: TimeInterval = 10,
                       file: StaticString = #filePath, line: UInt = #line,
                       condition: @MainActor () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(timeout))
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    let failure = LandmarkUIWaitTimeout(description: "\(description): not met within \(timeout) s")
    XCTFail(failure.description, file: file, line: line)
    throw failure
}

/// Distance from where `view` places its annotation's coordinate to where the map
/// projects that coordinate. MapKit anchors the view's centre minus `centerOffset`.
@MainActor
func anchorError(of view: MKAnnotationView, for annotation: MKAnnotation, in map: MKMapView) -> CGVector {
    let anchor = view.convert(CGPoint(x: view.bounds.midX - view.centerOffset.x,
                                      y: view.bounds.midY - view.centerOffset.y), to: map)
    let expected = map.convert(annotation.coordinate, toPointTo: map)
    return CGVector(dx: anchor.x - expected.x, dy: anchor.y - expected.y)
}
