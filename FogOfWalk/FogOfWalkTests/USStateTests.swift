import XCTest
@testable import FogOfWalk

final class USStateTests: XCTestCase {

    func testTableHasExactlyFiftyStates() {
        XCTAssertEqual(USState.abbreviationToFullName.count, 50)
        XCTAssertEqual(USState.allFullNames.count, 50)
        XCTAssertEqual(USState.count, 50)
    }

    func testAbbreviationResolvesToFullName() {
        XCTAssertEqual(USState.canonicalFullName(for: "NY"), "New York")
        XCTAssertEqual(USState.canonicalFullName(for: "ca"), "California")
    }

    func testFullNameIsCaseInsensitiveMatch() {
        XCTAssertEqual(USState.canonicalFullName(for: "texas"), "Texas")
        XCTAssertEqual(USState.canonicalFullName(for: "Texas"), "Texas")
    }

    func testUnrecognizedValueReturnsNil() {
        XCTAssertNil(USState.canonicalFullName(for: "Ontario"))
        XCTAssertNil(USState.canonicalFullName(for: ""))
        XCTAssertNil(USState.canonicalFullName(for: "Unknown"))
    }
}
