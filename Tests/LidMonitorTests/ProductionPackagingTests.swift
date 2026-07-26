import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionPackagingTests: XCTestCase {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    func testProductionPlistUsesFixedDaemonAndBoundedRestartContract() throws {
        let plist = try dictionary("packaging/launchd/com.crazydennies.macbook-lid-monitor.plist")
        XCTAssertEqual(plist["Label"] as? String, "com.crazydennies.macbook-lid-monitor")
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            ["/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon"]
        )
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(
            (plist["KeepAlive"] as? [String: Any])?["SuccessfulExit"] as? Bool,
            false
        )
        XCTAssertEqual(plist["ThrottleInterval"] as? Int, 30)
        XCTAssertEqual(plist["StandardOutPath"] as? String, "/Library/Logs/MacBookLidMonitor/production.log")
        XCTAssertFalse(String(describing: plist).contains("feasibility"))
    }

    func testConfigTemplateIsDisabledAndMatchesSchema() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("packaging/config/config.plist.example"))
        let config = try ProductionConfigurationDecoder().decode(data)
        XCTAssertEqual(config.mode, .disabled)
        XCTAssertEqual(config.sensorFreshness, 5)
    }

    func testManifestDefinesVersionedFixedArtifacts() throws {
        let plist = try dictionary("packaging/manifest/manifest.plist.example")
        XCTAssertEqual(plist["SchemaVersion"] as? Int, 1)
        XCTAssertEqual(plist["Product"] as? String, "macbook-lid-monitor-daemon")
        XCTAssertEqual(plist["BinaryPath"] as? String, "/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        XCTAssertEqual(plist["PlistPath"] as? String, "/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist")
        XCTAssertEqual(plist["ConfigPath"] as? String, ProductionConfigurationLoader.fixedPath)
    }

    private func dictionary(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
