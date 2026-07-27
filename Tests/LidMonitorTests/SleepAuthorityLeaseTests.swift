import Foundation
import XCTest
@testable import LidMonitorCore

final class SleepAuthorityLeaseTests: XCTestCase {
    func testSecondLeaseIsRejectedUntilFirstIsReleased() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbook-lid-monitor-authority-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let lease = POSIXSleepAuthorityLease(path: path)

        var first: SleepAuthorityHolding? = try lease.acquire()
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try lease.acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .alreadyHeld)
        }
        first = nil
        XCTAssertNoThrow(try lease.acquire())
    }

    func testSymlinkPathIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbook-lid-monitor-authority-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        let link = directory.appendingPathComponent("lease")
        FileManager.default.createFile(atPath: target.path, contents: Data())
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try POSIXSleepAuthorityLease(path: link.path).acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafePath)
        }
    }
}
