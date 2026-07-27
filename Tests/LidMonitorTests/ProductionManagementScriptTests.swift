import Foundation
import XCTest

final class ProductionManagementScriptTests: XCTestCase {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    func testScriptExposesOnlyNonMutatingCommandsAtThisStage() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("prepare)"))
        XCTAssertTrue(text.contains("verify)"))
        XCTAssertFalse(text.contains("launchctl"))
        XCTAssertFalse(text.contains("sudo"))
        XCTAssertFalse(text.contains("mkdir -p -- '/Library"))
        XCTAssertFalse(text.contains("cp -- \"$SOURCE_BINARY\" '/Library"))
    }

    func testPrepareAndVerifyEncodeVersionAndChecksumValidation() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("sha256_file"))
        XCTAssertTrue(text.contains("Set :Version"))
        XCTAssertTrue(text.contains("Set :BinarySHA256"))
        XCTAssertTrue(text.contains("test \"$expected\" = \"$actual\""))
        XCTAssertTrue(text.contains("test \"$version\" = \"$(package_version)\""))
    }

    func testScriptsContainFixedStagingPathAndSymlinkRefusal() throws {
        let main = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        let common = try String(contentsOf: root.appendingPathComponent("scripts/lib/production-package-common.sh"), encoding: .utf8)
        XCTAssertTrue(common.contains(".build/production-package"))
        XCTAssertTrue(common.contains("refusing symlink"))
        XCTAssertFalse(main.contains("/Library/LaunchDaemons"))
    }
}
