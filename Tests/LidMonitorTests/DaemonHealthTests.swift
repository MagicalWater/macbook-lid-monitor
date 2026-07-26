import Foundation
import XCTest
@testable import LidMonitorCore

final class DaemonHealthTests: XCTestCase {
    func testHealthSnapshotTracksStableStateAndErrorWithoutRawData() {
        var health = DaemonHealth(version: "1.0", mode: .dryRun, profileID: "profile")
        let date = Date(timeIntervalSince1970: 10)
        health.transition(to: .monitoringArmed, at: date)
        health.recordSample(at: date)
        health.recordError("unsupported-report")

        let snapshot = health.snapshot(now: date.addingTimeInterval(2))

        XCTAssertEqual(snapshot.state, .monitoringArmed)
        XCTAssertEqual(snapshot.lastValidSampleAge, 2)
        XCTAssertEqual(snapshot.lastErrorCode, "unsupported-report")
    }
}
