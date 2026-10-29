# Landmark rendering investigation evidence

**Date:** 2026-10-28. **Baseline:** `e64caa21b93348cca2954614b589c35496675aae`.
**Environment:** Xcode 27.1 (27A9275), iPhone 18 Pro simulator, iOS 27.0.

This record supports the [options proposal](../proposals/2026-10-28-landmark-map-responsiveness.md).
No production code was changed. No physical-device performance measurement was
performed and no personal exploration data was used as a fixture.

## Diagnostic results

Two temporary XCTest probes passed against the baseline:

- `testDiscoveredPinRoutesTouchAwayFromMap`: discovered pin hit testing returns
  the sibling overlay, outside the map subtree; the identical hint-only fixture
  returns a view in the map subtree. This verifies routing, not a synthesized
  finger drag or an end-to-end gesture-recognizer test.
- `testDrawThenResetLeavesAnchorAtOldLocalPosition`: real MapKit conversion and
  `LandmarkOverlayView` drawing with a +80-point layer translation leaves the
  drawn anchor 80 points left of its expected position after an identity reset
  (assertion tolerance 1 point). A subsequent draw with identity already set
  returns the anchor to the expected position. This isolates the production
  operation ordering; it does not invoke the coordinator or measure final-screen
  pixels across animation frames.

Both assertions intentionally describe current defects. They are diagnostic
probes, not desired-behavior regression tests. The temporary file was removed
before the full baseline suite and is not part of the shipped test target.

## Reproduce the probes

On the baseline revision, put the following source into
`FogOfWalk/FogOfWalkTests/LandmarkInvestigationProbeTests.swift`. The synchronized
Xcode folder includes it automatically. Run:

```sh
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:FogOfWalkTests/LandmarkInvestigationProbeTests test
```

Remove that temporary file afterwards. Result bundles and logs stayed outside
the repository. The source is preserved here so the result can be reproduced
without publishing simulator logs or a test that enshrines incorrect behavior.

```swift
import XCTest
import MapKit
@testable import FogOfWalk

// Temporary diagnostic probes, not regression tests for desired behavior.
@MainActor
final class LandmarkInvestigationProbeTests: XCTestCase {
    func testDiscoveredPinRoutesTouchAwayFromMap() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let container = UIView(frame: bounds)
        let map = MKMapView(frame: bounds)
        let overlay = LandmarkOverlayView(frame: bounds)
        container.addSubview(map)
        container.addSubview(overlay)
        overlay.coordinateToPoint = { _ in CGPoint(x: 200, y: 200) }
        let point = CGPoint(x: 200, y: 185)
        overlay.update(pins: [LandmarkPin(identifier: "Q1", name: "Fixture",
            category: "museum", coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            isDiscovered: true)])
        let discoveredHit = container.hitTest(point, with: nil)
        XCTAssertTrue(discoveredHit === overlay)
        XCTAssertFalse(discoveredHit!.isDescendant(of: map))
        overlay.update(pins: [LandmarkPin(identifier: "Q1", name: "Fixture",
            category: "museum", coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            isDiscovered: false)])
        let hintHit = container.hitTest(point, with: nil)
        XCTAssertTrue(hintHit === map || hintHit?.isDescendant(of: map) == true)
        print("LANDMARK_PROBE: discovered hit=overlay outside map subtree; hint hit=map subtree")
    }

    func testDrawThenResetLeavesAnchorAtOldLocalPosition() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let container = UIView(frame: bounds)
        let map = MKMapView(frame: bounds)
        let overlay = LandmarkOverlayView(frame: bounds)
        container.addSubview(map)
        container.addSubview(overlay)
        overlay.mapView = map
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: -74),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)), animated: false)
        let coordinate = map.convert(CGPoint(x: 200, y: 200), toCoordinateFrom: map)
        overlay.update(pins: [LandmarkPin(identifier: "Q1", name: "Fixture",
            category: "museum", coordinate: coordinate, isDiscovered: false)])
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.layer.transform = CATransform3DMakeTranslation(80, 0, 0)
        CATransaction.commit()
        var drawnPoint: CGPoint?
        overlay.coordinateToPoint = { [weak map, weak overlay] coordinate in
            let p = map!.convert(coordinate, toPointTo: overlay!)
            drawnPoint = p
            return p
        }
        // The current regionDidChangeAnimated order: draw, then identity.
        overlay.layer.displayIfNeeded()
        XCTAssertNotNil(drawnPoint)
        let pointInOldBasis = drawnPoint!
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.layer.transform = CATransform3DIdentity
        CATransaction.commit()
        let expected = map.convert(coordinate, toPointTo: container)
        let displayedAfterReset = overlay.convert(pointInOldBasis, to: container)
        XCTAssertEqual(displayedAfterReset.x - expected.x, -80, accuracy: 1)
        // Reversing the order fixes this isolated anchor problem.
        overlay.setNeedsDisplay()
        overlay.layer.displayIfNeeded()
        XCTAssertEqual(drawnPoint!.x, expected.x, accuracy: 1)
        print("LANDMARK_PROBE: draw-before-reset anchor error=\(displayedAfterReset.x - expected.x) pt; identity-before-draw error=\(drawnPoint!.x - expected.x) pt")
    }
}
```

## Compatibility with the PR base

Main advanced to `9e468e760f94f8de7fdfe653950e067945beacc2` during delivery. Its
changes to `MapContainerView`, `HeadingMapView`, `AGENTS.md` and `docs/SYSTEM.md`
were reviewed. The landmark transform, settle ordering, query and hit testing
are unchanged; the native-annotation option was updated to preserve the new
custom user-location view and follow-only heading behavior. The 303-test result
below belongs to the earlier probe baseline, not to this newer base.

An additional full-suite attempt on the newer base rebuilt successfully and
reported both landmark probes passing. It also reported a failure in
`MapHeadingTests.testCachedFirstReadingIsAcceptedButQueuedPreviousSessionCallbackIsRejected`
and repeated simulator app-launch errors. The run stalled during restart and
was interrupted; Xcode did not finalize a readable result bundle. This is **not
a full-suite pass** for the newer base. The cause of that heading-test/runtime
failure has not been diagnosed, and no fix or test suppression is included.
The temporary probe source was again removed; only documentation is delivered.

## Baseline build and full suite

After removing the temporary probe file, `xcodebuild test` built the app and ran
the full existing suite on the same simulator: **303 passed, 0 failed, 0 skipped**,
including the UI launch test. `xcresulttool get test-results summary` confirmed
the totals. There were no production Swift or test-source changes in this PR.
An unrelated app-icon working-tree edit appeared during the run and is excluded
from this investigation's patch; this result is not an exact byte-for-byte
baseline asset build.

```sh
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

This is baseline functional verification, not proof of gesture smoothness. The
source inspection, two probes and test-coverage gaps support the diagnosis;
physical-device profiling and a chosen implementation's regression suite remain
necessary to validate an improvement.
