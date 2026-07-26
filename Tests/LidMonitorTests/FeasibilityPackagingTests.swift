import Foundation
import XCTest
@testable import LidMonitorCore

final class FeasibilityPackagingTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPlistHasFixedDryRunSystemJobContract() throws {
        let url = projectRoot.appendingPathComponent("packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["Label"] as? String, "com.crazydennies.macbook-lid-monitor.feasibility")
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            ["/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike"]
        )
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["ProcessType"] as? String, "Background")
        XCTAssertGreaterThanOrEqual(plist["ThrottleInterval"] as? Int ?? 0, 30)
        XCTAssertNil(plist["KeepAlive"])
        XCTAssertNil(plist["UserName"])
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("execute-sleep") ?? true)
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("/bin/sh") ?? true)

        for key in ["StandardOutPath", "StandardErrorPath"] {
            if let path = plist[key] as? String {
                XCTAssertTrue(path.hasPrefix("/Library/Logs/MacBookLidMonitor/Feasibility/"))
            }
        }
    }

    func testManagementScriptUsesFixedAllowlistedSystemPaths() throws {
        let url = projectRoot.appendingPathComponent("scripts/manage-feasibility-daemon.sh")
        let script = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike"))
        XCTAssertTrue(script.contains("/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.feasibility.plist"))
        XCTAssertTrue(script.contains("/Library/Logs/MacBookLidMonitor/Feasibility"))
        XCTAssertFalse(script.contains("rm -rf"))
        XCTAssertFalse(script.contains("eval "))
        XCTAssertFalse(script.contains("--execute-sleep"))
        XCTAssertFalse(script.contains("macbook-lid-monitor-sleep-probe"))

        XCTAssertTrue(script.contains("feasibility artifacts already exist"))
        XCTAssertTrue(script.contains("test ! -L \"$SOURCE_BINARY\""))
        XCTAssertTrue(script.contains("trap - EXIT"))

        for command in ["prepare", "install", "bootstrap", "status", "logs", "stop", "bootout", "uninstall"] {
            XCTAssertTrue(script.contains("\(command)"), "missing subcommand \(command)")
        }
    }
}
