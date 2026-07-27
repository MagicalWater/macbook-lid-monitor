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

    func testAcceptTask10ExercisesInjectedRollbackUpgradeAndExplicitRollback() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-accept-task10-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let manifestURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/manifest.plist")
        var originalManifest = try plistDictionary(at: manifestURL)
        originalManifest["Version"] = "previous-version"
        try PropertyListSerialization.data(
            fromPropertyList: originalManifest,
            format: .xml,
            options: 0
        ).write(to: manifestURL)
        try synchronizeInstalledManifestChecksum(in: sandbox)

        try seedStaging()
        try runScript("accept-task10", environment: ["MLM_TEST_ROOT": sandbox.path])

        let finalManifest = try plistDictionary(at: manifestURL)
        XCTAssertEqual(finalManifest["Version"] as? String, "previous-version")
        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testAcceptTask10IsExplicitAndDoesNotHandlePasswords() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("accept-task10)"))
        XCTAssertTrue(text.contains("MLM_FAIL_UPGRADE_STAGE=after-activation"))
        XCTAssertFalse(text.contains("sudo -S"))
        XCTAssertFalse(text.contains("read -s"))
    }

    func testRotateLogsBoundsSizeAndKeepsThreeGenerations() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-log-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let logDir = sandbox.appendingPathComponent("Library/Logs/MacBookLidMonitor")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let log = logDir.appendingPathComponent("production.log")
        try Data(repeating: 65, count: 1_048_577).write(to: log)
        for index in 1...3 {
            try Data("old-\(index)".utf8).write(to: URL(fileURLWithPath: log.path + ".\(index)"))
        }

        try runScript("rotate-logs", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertEqual(try Data(contentsOf: log).count, 0)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: log.path + ".1")).count, 1_048_577)
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.path + ".3"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path + ".4"))
        let attributes = try FileManager.default.attributesOfItem(atPath: log.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: logDir.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testDiagnosticsIsRedactedAndDoesNotPrintLogContents() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("diagnostics label="))
        XCTAssertFalse(text.contains("tail -"))
        XCTAssertFalse(text.contains("cat \"$MANAGED_STDOUT_LOG\""))
        XCTAssertTrue(text.contains("pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true"))
    }

    func testUninstallRemovesOnlyManagedArtifactsAndPreservesUnrelatedFiles() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-uninstall-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let unrelated = sandbox.appendingPathComponent("Library/Application Support/Unrelated/keep.txt")
        try FileManager.default.createDirectory(at: unrelated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: unrelated)
        let logDir = sandbox.appendingPathComponent("Library/Logs/MacBookLidMonitor")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        for name in ["production.log", "production.log.1", "production-error.log.3"] {
            try Data("managed".utf8).write(to: logDir.appendingPathComponent(name))
        }

        try runScript("uninstall", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logDir.appendingPathComponent("production.log.1").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logDir.appendingPathComponent("production-error.log.3").path))
    }

    func testUninstallRejectsManagedSymlink() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-uninstall-symlink-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let config = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        try FileManager.default.removeItem(at: config)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: URL(fileURLWithPath: "/dev/null"))

        XCTAssertThrowsError(try runScript("uninstall", environment: ["MLM_TEST_ROOT": sandbox.path]))
    }

    func testUninstallRejectsRollbackDirectorySymlinkBeforeMutation() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-uninstall-rollback-symlink-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let support = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor")
        let rollback = support.appendingPathComponent("rollback")
        let target = sandbox.appendingPathComponent("outside-rollback")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: rollback, withDestinationURL: target)
        let binary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")

        XCTAssertThrowsError(try runScript("uninstall", environment: ["MLM_TEST_ROOT": sandbox.path]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: binary.path))
    }

    func testAcceptTask11RotatesDiagnosesUninstallsAndLeavesNoManagedResidual() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-accept-task11-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let logDirectory = sandbox.appendingPathComponent("Library/Logs/MacBookLidMonitor")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 1_048_577)
            .write(to: logDirectory.appendingPathComponent("production.log"))
        try Data(repeating: 0x42, count: 1_048_577)
            .write(to: logDirectory.appendingPathComponent("production-error.log"))

        try runScript("accept-task11", environment: ["MLM_TEST_ROOT": sandbox.path])

        let managedPaths = [
            sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon"),
            sandbox.appendingPathComponent("Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist"),
            sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist"),
            sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/manifest.plist"),
            logDirectory.appendingPathComponent("production.log"),
            logDirectory.appendingPathComponent("production.log.1"),
            logDirectory.appendingPathComponent("production-error.log"),
            logDirectory.appendingPathComponent("production-error.log.1"),
        ]
        for path in managedPaths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), path.path)
        }
    }

    func testAcceptTask11IsExplicitAndDoesNotHandlePasswords() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("accept-task11)"))
        XCTAssertTrue(text.contains("verify_uninstalled_state"))
        XCTAssertFalse(text.contains("sudo -S"))
        XCTAssertFalse(text.contains("read -s"))
    }

    func testAcceptTask12LoggedInInstallsDryRunsAndReturnsDisabled() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-accept-task12-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("accept-task12-logged-in", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon").path))
    }

    func testAcceptTask12LoggedInIsExplicitAndDoesNotHandlePasswords() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("accept-task12-logged-in)"))
        XCTAssertTrue(text.contains("verify_logged_in_dry_run"))
        XCTAssertTrue(text.contains("trap cleanup_task12_to_disabled EXIT"))
        XCTAssertFalse(text.contains("sudo -S"))
        XCTAssertFalse(text.contains("read -s"))
    }

    func testTask12LoginwindowTwoPhaseAcceptanceUsesEvidenceAndReturnsDisabled() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-task12-loginwindow-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("accept-task12-loginwindow-start", environment: ["MLM_TEST_ROOT": sandbox.path, "SUDO_USER": "water"])
        try runScript("accept-task12-loginwindow-finish", environment: ["MLM_TEST_ROOT": sandbox.path, "SUDO_USER": "water"])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/task12-loginwindow-evidence.txt").path))
    }

    func testTask12LoginwindowCommandsAreExplicitAndDoNotHandlePasswords() throws {
        let text = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("accept-task12-loginwindow-start)"))
        XCTAssertTrue(text.contains("accept-task12-loginwindow-finish)"))
        XCTAssertTrue(text.contains("launchctl bootout \"gui/$invoking_uid\""))
        XCTAssertTrue(text.contains("launchctl bootstrap system \"$observer_plist\""))
        XCTAssertTrue(text.contains("com.crazydennies.macbook-lid-monitor.task12-loginwindow-observer"))
        XCTAssertFalse(text.contains("nohup \"$helper\""))
        XCTAssertTrue(text.contains("trap cleanup_task12_loginwindow_to_disabled EXIT"))
        XCTAssertTrue(text.contains("\\$count\" == 1"))
        XCTAssertTrue(text.contains("\\$job\" == loaded"))
        XCTAssertTrue(text.contains("stable=\\$((stable + 1))"))
        XCTAssertFalse(text.contains("sudo -S"))
        XCTAssertFalse(text.contains("read -s"))
    }

    func testTask12LoginwindowInvalidEvidenceStillReturnsDisabled() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-task12-loginwindow-invalid-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        var plist = try plistDictionary(at: configURL)
        plist["Mode"] = "dry-run"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: configURL)
        let evidence = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/task12-loginwindow-evidence.txt")
        try Data("console-user=_windowserver\nprocess-count=0\nsystem-job=absent\n".utf8).write(to: evidence)

        XCTAssertThrowsError(
            try runScript("accept-task12-loginwindow-finish", environment: ["MLM_TEST_ROOT": sandbox.path, "SUDO_USER": "water"])
        )

        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testTask12SleepWakeAcceptanceUsesWakeEvidenceAndReturnsDisabled() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-task12-sleep-wake-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("accept-task12-sleep-wake", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testTask12SleepWakeCommandIsExplicitAndFailSafe() throws {
        let text = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("accept-task12-sleep-wake)"))
        XCTAssertTrue(text.contains("prepare_as_invoking_user"))
        XCTAssertTrue(text.contains("upgrade_package"))
        XCTAssertTrue(text.contains("/usr/bin/pmset sleepnow"))
        XCTAssertTrue(text.contains("wake-recovery production evidence missing"))
        XCTAssertTrue(text.contains("trap cleanup_task12_sleep_wake_to_disabled EXIT"))
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

    func testUpgradeReplacesManagedVersionAndKeepsOneRollbackSlot() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-upgrade-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        try Data("old".utf8).write(to: installedBinary)
        try synchronizeInstalledManifestChecksum(in: sandbox)

        try seedStaging()
        try runScript("upgrade", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertEqual(try Data(contentsOf: installedBinary), try Data(contentsOf: root.appendingPathComponent(".build/production-package/macbook-lid-monitor-daemon")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/rollback/macbook-lid-monitor-daemon").path))
    }

    func testUpgradeFailureAutomaticallyRestoresPreviousSet() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-upgrade-failure-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        let previous = Data("previous-version".utf8)
        try previous.write(to: installedBinary)
        try synchronizeInstalledManifestChecksum(in: sandbox)
        try seedStaging()

        XCTAssertThrowsError(
            try runScript(
                "upgrade",
                environment: [
                    "MLM_TEST_ROOT": sandbox.path,
                    "MLM_FAIL_UPGRADE_STAGE": "after-activation",
                ]
            )
        )
        XCTAssertEqual(try Data(contentsOf: installedBinary), previous)
    }

    func testUpgradeRejectsCorruptInstalledManifestBeforeActivation() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-upgrade-corrupt-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let manifest = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/manifest.plist")
        var value = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: manifest), format: nil) as? [String: Any]
        )
        value["BinarySHA256"] = "corrupt"
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: manifest)

        XCTAssertThrowsError(try runScript("upgrade", environment: ["MLM_TEST_ROOT": sandbox.path]))
    }

    func testRollbackFailureLeavesNewSetInactiveAndReturnsFailure() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-rollback-failure-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try seedStaging()

        XCTAssertThrowsError(
            try runScript(
                "upgrade",
                environment: [
                    "MLM_TEST_ROOT": sandbox.path,
                    "MLM_FAIL_UPGRADE_STAGE": "rollback-restore",
                ]
            )
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

    private func synchronizeInstalledManifestChecksum(in sandbox: URL) throws {
        let binary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        let manifestURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/manifest.plist")
        var manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: manifestURL),
                format: nil
            ) as? [String: Any]
        )
        manifest["BinarySHA256"] = try commandOutput(
            "/usr/bin/shasum",
            ["-a", "256", binary.path]
        ).split(separator: " ").first.map(String.init)
        try PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .xml,
            options: 0
        ).write(to: manifestURL)
    }

    private func plistDictionary(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: url),
                format: nil
            ) as? [String: Any]
        )
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
