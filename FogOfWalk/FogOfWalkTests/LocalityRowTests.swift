import XCTest
import SwiftUI
import MapKit
@testable import FogOfWalk

@MainActor
final class LocalityRowTests: XCTestCase {

    private func stat(_ name: String, _ count: Int) -> LocalityStats {
        LocalityStats(name: name, count: count,
                      center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                      span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
    }

    /// Leftmost x of the accent-coloured bar fill in a rendered row.
    private func barStartX(for stat: LocalityStats, maxCount: Int) throws -> Int {
        let renderer = ImageRenderer(content:
            LocalityRow(stat: stat, maxCount: maxCount, action: {})
                .frame(width: 360)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let buffer = pixelBuffer(for: image)
        let midY = CGFloat(image.height / 2)
        for x in 0..<image.width {
            let p = pixelColor(at: CGPoint(x: CGFloat(x), y: midY), in: buffer,
                               width: image.width, height: image.height)
            if p.b > 200 && p.r < 120 { return x }
        }
        XCTFail("No bar fill found for \(stat.name)")
        return -1
    }

    // Regression: a grouped count such as "1,234" overflowed the count column and pushed
    // that row's bar left of the others.
    func testBarsAlignWhenCountWidthsDiffer() throws {
        let wide = try barStartX(for: stat("San Francisco", 1234), maxCount: 1234)
        let narrow = try barStartX(for: stat("Oakland", 87), maxCount: 1234)
        XCTAssertEqual(wide, narrow)
    }

    func testFillWidthScalesWithCount() {
        XCTAssertEqual(LocalityRow.fillWidth(count: 50, maxCount: 100, trackWidth: 80, minimum: 8), 40)
        XCTAssertEqual(LocalityRow.fillWidth(count: 100, maxCount: 100, trackWidth: 80, minimum: 8), 80)
    }

    func testSmallNonzeroCountGetsMinimumFill() {
        XCTAssertEqual(LocalityRow.fillWidth(count: 1, maxCount: 1000, trackWidth: 80, minimum: 8), 8)
    }

    func testZeroCountHasNoFill() {
        XCTAssertEqual(LocalityRow.fillWidth(count: 0, maxCount: 100, trackWidth: 80, minimum: 8), 0)
        XCTAssertEqual(LocalityRow.fillWidth(count: 5, maxCount: 0, trackWidth: 80, minimum: 8), 0)
    }
}
