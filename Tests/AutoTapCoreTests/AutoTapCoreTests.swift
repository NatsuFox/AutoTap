import XCTest
@testable import AutoTapCore

final class AutoTapCoreTests: XCTestCase {
    func testRestoredCopyProducesNewIdentityAndStopsRunning() {
        var unit = ClickUnit.defaultPointGroup(index: 1)
        unit.isRunning = true
        let originalUnitID = unit.id
        let originalPointIDs = unit.groupPoints.map { $0.id }

        let restored = unit.restoredCopy()

        XCTAssertFalse(restored.isRunning)
        XCTAssertNotEqual(restored.id, originalUnitID)
        XCTAssertEqual(restored.kind, .pointGroup)
        XCTAssertEqual(restored.groupPoints.count, unit.groupPoints.count)
        XCTAssertNotEqual(restored.groupPoints.map { $0.id }, originalPointIDs)
    }

    func testHistoryRecordStoresStoppedSnapshot() {
        var unit = ClickUnit.defaultSinglePoint(index: 1)
        unit.isRunning = true

        let record = HistoryRecord(label: "Saved Point", unit: unit)

        XCTAssertEqual(record.label, "Saved Point")
        XCTAssertFalse(record.snapshot.isRunning)
        XCTAssertEqual(record.snapshot.kind, .singlePoint)
    }

    func testGroupSanitizationKeepsAtLeastOnePoint() {
        let unit = ClickUnit(
            name: "",
            kind: .pointGroup,
            frequencyHz: 0,
            singlePoint: ScreenPoint(name: "Point"),
            groupPoints: []
        ).sanitized()

        XCTAssertEqual(unit.kind, .pointGroup)
        XCTAssertEqual(unit.groupPoints.count, 1)
        XCTAssertEqual(unit.name, ClickUnitKind.pointGroup.defaultName)
        XCTAssertEqual(unit.frequencyHz, 0.1, accuracy: 0.0001)
    }
}
