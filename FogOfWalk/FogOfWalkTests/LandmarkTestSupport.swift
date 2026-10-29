import XCTest
import Foundation

/// Deadline-bounded polling yields to UIKit/MapKit. The poller expires before the
/// waiter, and is cancelled and joined before returning, so it cannot fulfill late.
func waitForLandmarkUI(_ description: String, timeout: TimeInterval = 10,
                       file: StaticString = #filePath, line: UInt = #line,
                       condition: @escaping @MainActor () -> Bool) async throws {
    let ready = XCTestExpectation(description: description)
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(timeout))
    let polling = Task { @MainActor in
        while !Task.isCancelled && clock.now < deadline {
            if condition() {
                guard !Task.isCancelled && clock.now < deadline else { return }
                ready.fulfill()
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
    let result = await XCTWaiter.fulfillment(of: [ready], timeout: timeout + 1)
    polling.cancel()
    await polling.value
    _ = try XCTUnwrap(result == .completed ? true : nil, description, file: file, line: line)
}
