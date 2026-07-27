import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionManagementScriptTests: XCTestCase {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    func testScriptRequiresExplicitLifecycleCommandsWithoutSudoEscalation() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("prepare)"))
        XCTAssertTrue(text.contains("verify)"))
        XCTAssertTrue(text.contains("launchctl_system"))
        XCTAssertTrue(text.contains("sudo -u \"$invoking_user\" -H"))
        XCTAssertFalse(text.contains("sudo -S"))
        XCTAssertFalse(text.contains("sudo sh"))
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
        XCTAssertFalse(main.contains("MLM_TEST_ROOT=/"))
    }

    func testLifecycleCommandsOperateAgainstSandboxRoot() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-test-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("status", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("disable", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("stop", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootout", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist").path))
        let config = try Data(contentsOf: sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist"))
        let decoded = try ProductionConfigurationDecoder().decode(config)
        XCTAssertEqual(decoded.mode, .disabled)
    }

    func testAcceptTask9RunsCompleteLifecycleAgainstSandboxRoot() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-accept-task9-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("accept-task9", environment: ["MLM_TEST_ROOT": sandbox.path])

        let binary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        let plist = sandbox.appendingPathComponent("Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist")
        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plist.path))
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testAcceptTask9IsExplicitAndDoesNotEmbedPasswordHandling() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("accept-task9)"))
        XCTAssertTrue(text.contains("prepare_as_invoking_user"))
        XCTAssertFalse(text.contains("sudo -S"))
        XCTAssertFalse(text.contains("read -s"))
    }

    func testInstallRejectsManagedPathSymlink() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-symlink-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let target = sandbox.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let library = sandbox.appendingPathComponent("Library")
        try FileManager.default.createSymbolicLink(at: library, withDestinationURL: target)

        try seedStaging()
        XCTAssertThrowsError(try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path]))
    }

    func testInstallPreservesUnrelatedFiles() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-unrelated-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let unrelated = sandbox.appendingPathComponent("Library/Application Support/Unrelated/keep.txt")
        try FileManager.default.createDirectory(at: unrelated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: unrelated)

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "keep")
    }

    func testInstallStartsFromDisabledConfiguration() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-disabled-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testStatusFailsWhenPackageIsNotInstalled() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-missing-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        XCTAssertThrowsError(try runScript("status", environment: ["MLM_TEST_ROOT": sandbox.path]))
    }

    func testInstallRejectsNonDisabledStagingConfiguration() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-nondisabled-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        let configURL = root.appendingPathComponent(".build/production-package/config.plist")
        let data = try Data(contentsOf: configURL)
        var plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        plist["Mode"] = "dry-run"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: configURL)

        XCTAssertThrowsError(try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path]))
    }

    func testTestRootOutsideRepositoryBuildIsRejected() throws {
        XCTAssertThrowsError(
            try runScript("status", environment: ["MLM_TEST_ROOT": "/tmp/macbook-lid-monitor-test-root"])
        )
    }

    private func seedStaging() throws {
        let staging = root.appendingPathComponent(".build/production-package")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let binary = staging.appendingPathComponent("macbook-lid-monitor-daemon")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        try FileManager.default.copyItem(
            at: root.appendingPathComponent("packaging/launchd/com.crazydennies.macbook-lid-monitor.plist"),
            to: staging.appendingPathComponent("com.crazydennies.macbook-lid-monitor.plist")
        )
        try FileManager.default.copyItem(
            at: root.appendingPathComponent("packaging/config/config.plist.example"),
            to: staging.appendingPathComponent("config.plist")
        )

        let manifestSource = root.appendingPathComponent("packaging/manifest/manifest.plist.example")
        let manifestURL = staging.appendingPathComponent("manifest.plist")
        let sourceData = try Data(contentsOf: manifestSource)
        var manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: sourceData, format: nil) as? [String: Any]
        )
        manifest["Version"] = try commandOutput("/usr/bin/git", ["rev-parse", "--short=12", "HEAD"])
        manifest["BinarySHA256"] = try commandOutput("/usr/bin/shasum", ["-a", "256", binary.path])
            .split(separator: " ").first.map(String.init)
        let data = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        try data.write(to: manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    private func commandOutput(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ProductionManagementScriptTests", code: Int(process.terminationStatus))
        }
        return output
    }

    private func runScript(_ command: String, environment: [String: String] = [:]) throws {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/manage-production-daemon.sh", command]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ProductionManagementScriptTests",
                code: Int(process.terminationStatus),
                userInfo: nil
            )
        }
    }
}
