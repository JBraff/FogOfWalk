import XCTest
@testable import FogOfWalk

/// The recovery alert's text is derived only from the notice it presents, so it cannot
/// change when dismissal clears `ExplorationStore.recoveryNotice`.
final class RecoveryAlertTextTests: XCTestCase {
    func testTextDescribesEachRecoveryOutcome() async {
        await MainActor.run {
            let unusable = StoreRecoveryNotice(backupURLs: [], storeIsUsable: false)
            XCTAssertEqual(ContentView.recoveryTitle(for: unusable), "Exploration Storage Unavailable")
            XCTAssertTrue(ContentView.recoveryMessage(for: unusable).contains("won\u{2019}t be saved"))

            let reset = StoreRecoveryNotice(backupURLs: [], storeIsUsable: true)
            XCTAssertEqual(ContentView.recoveryTitle(for: reset), "Exploration History Reset")
            XCTAssertFalse(ContentView.recoveryMessage(for: reset).contains("copy"))

            let backedUp = StoreRecoveryNotice(backupURLs: [URL(fileURLWithPath: "/tmp/x")],
                                               storeIsUsable: true)
            XCTAssertTrue(ContentView.recoveryMessage(for: backedUp).contains("A copy of the old data"))
        }
    }
}
