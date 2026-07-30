import XCTest
@testable import FogOfWalk

final class BackupServiceTests: XCTestCase {

    private func samplePayload() -> BackupPayload {
        BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            visitedCells: [
                BackupVisitedCell(cellX: 1, cellY: 2, cellSizeMeters: 50.0,
                                   firstVisited: Date(timeIntervalSince1970: 1_600_000_000),
                                   locality: "Springfield")
            ],
            landmarks: [
                BackupLandmark(identifier: "Q42", firstDiscovered: Date(timeIntervalSince1970: 1_650_000_000))
            ]
        )
    }

    func testEncodeDecodeRoundTrip() throws {
        let payload = samplePayload()
        let data = try BackupService.encode(payload)
        let decoded = try BackupService.decode(data)
        XCTAssertEqual(decoded, payload)
    }

    func testDecodeRejectsUnsupportedSchemaVersion() throws {
        var payload = samplePayload()
        payload = BackupPayload(schemaVersion: 999, exportedAt: payload.exportedAt,
                                 visitedCells: payload.visitedCells, landmarks: payload.landmarks)
        let data = try BackupService.encode(payload)

        XCTAssertThrowsError(try BackupService.decode(data)) { error in
            guard let backupError = error as? BackupError else {
                return XCTFail("Expected BackupError, got \(error)")
            }
            XCTAssertEqual(backupError, .unsupportedSchemaVersion(999))
        }
    }

    func testDecodeRejectsMalformedJSON() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try BackupService.decode(garbage))
    }
}
