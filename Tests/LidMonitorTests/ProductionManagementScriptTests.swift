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

    func testProductionRunbookDocumentsOnlyRealManagementCommandsAndStateSemantics() throws {
        let runbookURL = root.appendingPathComponent("docs/operations/production-daemon.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: runbookURL.path))
        let runbook = try String(contentsOf: runbookURL, encoding: .utf8)
        let manager = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        let documentedCommands = [
            "status", "diagnostics", "disable", "reset-crash-budget", "rotate-logs",
            "upgrade", "rollback", "uninstall", "bootout", "operational-baseline",
        ]
        for command in documentedCommands {
            XCTAssertTrue(runbook.contains("manage-production-daemon.sh \(command)"), command)
            XCTAssertTrue(manager.contains("\(command))"), command)
        }
        for requiredText in [
            "foreground real-sleep conflict",
            "circuit-open recovery",
            "integrity failure",
            "emergency bootout",
            "leaves enabled",
            "forces disabled",
            "real sleep warning",
            "reboot warning",
        ] {
            XCTAssertTrue(runbook.contains(requiredText), requiredText)
        }
        XCTAssertFalse(runbook.contains("manage-production-daemon.sh enable"))
    }

    func testPrepareAndVerifyEncodeVersionAndChecksumValidation() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("sha256_file"))
        XCTAssertTrue(text.contains("Set :Version"))
        XCTAssertTrue(text.contains("Set :BinarySHA256"))
        XCTAssertTrue(text.contains("Set :SourceCommit"))
        XCTAssertTrue(text.contains("Set :PlistSHA256"))
        XCTAssertTrue(text.contains("Set :DisabledConfigSHA256"))
        XCTAssertTrue(text.contains("normalized_config_sha256"))
        XCTAssertTrue(text.contains("test \"$expected\" = \"$actual\""))
        XCTAssertTrue(text.contains("test \"$version\" = \"$(package_version)\""))
        XCTAssertTrue(text.contains("git -c safe.directory=\"$REPO_ROOT\" -C \"$REPO_ROOT\" rev-parse HEAD"))
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
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        try Data("task10-previous-payload".utf8).write(to: installedBinary)
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

    func testRotateLogsPreservesActiveWriterInodeAndPrimaryPath() throws {
        let sandbox = root.appendingPathComponent(".build/production-log-running-writer-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let logDir = sandbox.appendingPathComponent("Library/Logs/MacBookLidMonitor")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let log = logDir.appendingPathComponent("production.log")
        try Data(repeating: 65, count: 1_048_577).write(to: log)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let originalInode = try XCTUnwrap(
            (FileManager.default.attributesOfItem(atPath: log.path)[.systemFileNumber] as? NSNumber)?.uint64Value
        )

        try runScript("rotate-logs", environment: ["MLM_TEST_ROOT": sandbox.path])
        try handle.write(contentsOf: Data("post-rotation-event\n".utf8))
        try handle.synchronize()

        let currentInode = try XCTUnwrap(
            (FileManager.default.attributesOfItem(atPath: log.path)[.systemFileNumber] as? NSNumber)?.uint64Value
        )
        XCTAssertEqual(currentInode, originalInode)
        let current = String(decoding: try Data(contentsOf: log), as: UTF8.self)
        XCTAssertTrue(current.contains("post-rotation-event"), current)
        XCTAssertEqual(try Data(contentsOf: logDir.appendingPathComponent("production.log.1")).count, 1_048_577)
    }

    func testObservabilityDefinesOnlineSafeRotationInterface() throws {
        let observability = try String(
            contentsOf: root.appendingPathComponent("scripts/lib/production-observability.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(observability.contains("rotate_one_log_preserving_inode()"))
        XCTAssertTrue(observability.contains("rotate_logs()"))
    }

    func testRotateLogsRejectsGenerationSymlinkBeforeMutation() throws {
        let sandbox = root.appendingPathComponent(".build/production-log-generation-symlink-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let logDir = sandbox.appendingPathComponent("Library/Logs/MacBookLidMonitor")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let log = logDir.appendingPathComponent("production.log")
        let outside = sandbox.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        try Data(repeating: 65, count: 1_048_577).write(to: log)
        try FileManager.default.createSymbolicLink(at: logDir.appendingPathComponent("production.log.1"), withDestinationURL: outside)

        let failure = try runScriptFailure("rotate-logs", environment: ["MLM_TEST_ROOT": sandbox.path])
        XCTAssertTrue(failure.output.contains("error=log-rotation-unsafe"), failure.output)
        XCTAssertEqual(String(decoding: try Data(contentsOf: outside), as: UTF8.self), "outside")
        XCTAssertEqual(try Data(contentsOf: log).count, 1_048_577)
    }

    func testDiagnosticsIsRedactedAndDoesNotPrintLogContents() throws {
        let manager = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        let observability = try String(
            contentsOf: root.appendingPathComponent("scripts/lib/production-observability.sh"),
            encoding: .utf8
        )
        let text = manager + observability
        XCTAssertTrue(observability.contains("diagnostics()"))
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
        let support = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor")
        let managedStateNames = [
            "sleep-authority.lock",
            "deployment-acceptance.plist",
            "deployment-reboot.plist",
            "health.plist",
            "crash-budget.json",
            "task14-reboot-state",
        ]
        for name in managedStateNames {
            try Data("managed-state".utf8).write(to: support.appendingPathComponent(name))
        }
        let rollback = support.appendingPathComponent("rollback")
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
        try Data("rollback".utf8).write(to: rollback.appendingPathComponent("manifest.plist"))

        try runScript("uninstall", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logDir.appendingPathComponent("production.log.1").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logDir.appendingPathComponent("production-error.log.3").path))
        for name in managedStateNames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent(name).path), name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rollback.path))
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
        let config = support.appendingPathComponent("config.plist")
        var enabled = try plistDictionary(at: config)
        enabled["Mode"] = "enabled"
        try PropertyListSerialization.data(fromPropertyList: enabled, format: .xml, options: 0).write(to: config)

        XCTAssertThrowsError(try runScript("uninstall", environment: ["MLM_TEST_ROOT": sandbox.path]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: binary.path))
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: config)).mode, .enabled)
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

    func testDeploymentDryRunSleepWakeUsesInstalledIdentityAndReturnsDisabled() throws {
        let sandbox = root.appendingPathComponent(".build/production-deployment-dry-run-sleep-wake-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("deployment-dry-run", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("deployment-dry-run-sleep-wake", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testDeploymentDryRunReopenRearmsSameInstalledDaemonAndReturnsDisabled() throws {
        let sandbox = root.appendingPathComponent(".build/production-deployment-dry-run-reopen-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("deployment-dry-run", environment: ["MLM_TEST_ROOT": sandbox.path])
        let output = try runScriptOutput(
            "deployment-dry-run-reopen",
            environment: ["MLM_TEST_ROOT": sandbox.path]
        )

        XCTAssertTrue(output.contains("would-sleep=true"), output)
        XCTAssertTrue(output.contains("rearmed=true"), output)
        XCTAssertTrue(output.contains("pid-stable=true"), output)

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

    func testTask13EnabledOnceAcceptanceReturnsDisabledInSandbox() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-task13-enabled-once-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("accept-task13-enabled-once", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testTask13EnabledOnceCommandIsExplicitExactlyOnceAndFailSafe() throws {
        let text = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("accept-task13-enabled-once)"))
        XCTAssertTrue(text.contains("set_managed_mode enabled"))
        XCTAssertTrue(text.contains("expected exactly one sleep-request-attempted event"))
        XCTAssertTrue(text.contains("expected at most one sleep-requested return event"))
        XCTAssertTrue(text.contains("attempt-count=1 return-count=%s"))
        XCTAssertTrue(text.contains("trap cleanup_task13_enabled_once_to_disabled EXIT"))
        XCTAssertTrue(text.contains("action=close-lid-within-180-seconds"))
        XCTAssertFalse(text.contains("sudo -S"))
        XCTAssertFalse(text.contains("read -s"))
    }

    func testTask13RecoveryResleepAcceptanceReturnsDisabledInSandbox() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-task13-recovery-resleep-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("accept-task13-recovery-resleep", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testTask13RecoveryResleepCommandIsBoundedExactlyTwiceAndFailSafe() throws {
        let text = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("accept-task13-recovery-resleep)"))
        XCTAssertTrue(text.contains("expected exactly two sleep-request-attempted events"))
        XCTAssertTrue(text.contains("expected exactly one recovery-resleep event"))
        XCTAssertTrue(text.contains("expected two wake-recovery events"))
        XCTAssertTrue(text.contains("trap cleanup_task13_recovery_resleep_to_disabled EXIT"))
        XCTAssertTrue(text.contains("after-first-wake-keep-lid-below-68-degrees-for-15-seconds"))
        XCTAssertFalse(text.contains("sudo -S"))
        XCTAssertFalse(text.contains("read -s"))
    }

    func testDeployableProductionScriptContainsNoSleepOperationOverride() throws {
        let text = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        XCTAssertFalse(text.contains("accept-task13-injected-failure"))
        XCTAssertFalse(text.contains("MLM_SLEEP_OPERATION"))
        XCTAssertFalse(text.contains("Add :EnvironmentVariables"))
        XCTAssertFalse(text.contains("Delete :EnvironmentVariables"))
    }

    func testTask14RebootRollbackAndUninstallAcceptanceInSandbox() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-task14-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])

        let manifest = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/manifest.plist")
        _ = try commandOutput(
            "/usr/libexec/PlistBuddy",
            ["-c", "Set :Version task14-previous-version", manifest.path]
        )
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        try Data("task14-previous-payload".utf8).write(to: installedBinary)
        try synchronizeInstalledManifestChecksum(in: sandbox)
        try runScript("accept-task14-reboot-start", environment: [
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_BOOT_EPOCH": "1700000000",
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))

        try runScript("accept-task14-reboot-finish", environment: [
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_BOOT_EPOCH": "1700000100",
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
    }

    func testTask14CommandsRequireRebootProofAndPerformRollbackThenUninstall() throws {
        let text = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("accept-task14-reboot-start)"))
        XCTAssertTrue(text.contains("accept-task14-reboot-finish)"))
        XCTAssertTrue(text.contains("reboot not detected"))
        XCTAssertTrue(text.contains("migration=legacy-usec"))
        XCTAssertTrue(text.contains("usec = [0-9]+"))
        XCTAssertTrue(text.contains("verified task=14 scope=rollback"))
        XCTAssertTrue(text.contains("verify_uninstalled_state"))
        XCTAssertFalse(text.contains("shutdown -r"))
        XCTAssertFalse(text.contains("reboot" + " now"))
    }

    func testCrashBudgetResetRequiresDisabledInstalledNonresidentState() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-crash-reset-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let budget = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/crash-budget.json")
        try Data("{}".utf8).write(to: budget)

        try runScript("reset-crash-budget", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertFalse(FileManager.default.fileExists(atPath: budget.path))
    }

    func testCrashBudgetResetCommandIsExplicitAndFailSafe() throws {
        let text = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("reset-crash-budget) reset_crash_budget"))
        XCTAssertTrue(text.contains("crash budget reset requires disabled mode"))
        XCTAssertTrue(text.contains("crash budget reset requires no resident daemon"))
        XCTAssertTrue(text.contains("refusing symlink crash budget path"))
        XCTAssertFalse(text.contains("reset-crash-budget) set_enabled_mode"))
    }

    func testTask13DryRunPathAcceptanceReturnsDisabledInSandbox() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-task13-dry-run-path-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("accept-task13-dry-run-path", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        let config = try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL))
        XCTAssertEqual(config.mode, .disabled)
    }

    func testTask13DryRunPathCommandRequiresFullDiagnosticChainAndFailSafe() throws {
        let text = try String(contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("accept-task13-dry-run-path)"))
        XCTAssertTrue(text.contains("candidate-started evidence missing"))
        XCTAssertTrue(text.contains("debounce-elapsed evidence missing"))
        XCTAssertTrue(text.contains("expected exactly one sleep-request-attempted event"))
        XCTAssertTrue(text.contains("expected exactly one would-sleep event"))
        XCTAssertTrue(text.contains("trap cleanup_task13_dry_run_path_to_disabled EXIT"))
        XCTAssertTrue(text.contains("monitoring-armed readiness missing"))
        XCTAssertTrue(text.contains("ready task=13 scope=dry-run-path"))
        XCTAssertTrue(text.contains("event=transition.*pid=$daemon_pid.*name=monitoring-armed"))
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

    func testInstallCreatesSecureManagedSleepAuthorityLease() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-lease-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        let lease = sandbox.appendingPathComponent(
            "Library/Application Support/MacBookLidMonitor/sleep-authority.lock"
        )
        let metadata = try FileManager.default.attributesOfItem(atPath: lease.path)
        XCTAssertEqual(metadata[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(metadata[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
        XCTAssertEqual(metadata[.referenceCount] as? NSNumber, NSNumber(value: 1))
        XCTAssertEqual(try Data(contentsOf: lease).count, 0)
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

    func testUpgradeRepairsLegacyInstallMissingManagedSleepAuthorityBeforeNoOp() throws {
        let sandbox = root.appendingPathComponent(".build/production-package-upgrade-lease-repair-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let lease = sandbox.appendingPathComponent(
            "Library/Application Support/MacBookLidMonitor/sleep-authority.lock"
        )
        try FileManager.default.removeItem(at: lease)

        try seedStaging()
        try runScript("upgrade", environment: ["MLM_TEST_ROOT": sandbox.path])

        let metadata = try FileManager.default.attributesOfItem(atPath: lease.path)
        XCTAssertEqual(metadata[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(metadata[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
        XCTAssertEqual(metadata[.referenceCount] as? NSNumber, NSNumber(value: 1))
    }

    func testMaintenanceTransactionsExposeExplicitDisabledBoundaries() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        for interface in [
            "prepare_maintenance_disabled_state()",
            "backup_current_set()",
            "activate_staged_set_disabled()",
            "restore_rollback_set_disabled()",
            "upgrade_package()",
            "rollback_upgrade()",
            "uninstall_package()",
        ] {
            XCTAssertTrue(text.contains(interface), interface)
        }
        XCTAssertTrue(text.contains("prepare_maintenance_disabled_state\n    backup_current_set"))
        XCTAssertTrue(text.contains("prepare_maintenance_disabled_state\n    restore_rollback_set_disabled"))
    }

    func testUpgradeForcesDisabledAndInvalidatesAcceptanceWhenPayloadChanges() throws {
        let sandbox = root.appendingPathComponent(".build/production-maintenance-upgrade-disabled-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        _ = try runDeploymentLibrary(
            "record_deployment_acceptance deployment-dry-run pass",
            sandbox: sandbox
        )
        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        var enabled = try plistDictionary(at: configURL)
        enabled["Mode"] = "enabled"
        try PropertyListSerialization.data(fromPropertyList: enabled, format: .xml, options: 0).write(to: configURL)
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        try Data("old-payload".utf8).write(to: installedBinary)
        try synchronizeInstalledManifestChecksum(in: sandbox)

        try seedStaging()
        try runScript("upgrade", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertEqual(
            try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL)).mode,
            .disabled
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist").path
        ))
    }

    func testEvidenceOnlyUpgradeUpdatesInstalledProvenanceAndInvalidatesAcceptance() throws {
        let sandbox = root.appendingPathComponent(".build/production-maintenance-evidence-only-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        _ = try runDeploymentLibrary(
            "record_deployment_acceptance deployment-dry-run pass",
            sandbox: sandbox
        )
        let installedManifest = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/manifest.plist")
        var installed = try plistDictionary(at: installedManifest)
        installed["Version"] = "legacy-evidence"
        installed["SourceCommit"] = String(repeating: "a", count: 40)
        try PropertyListSerialization.data(fromPropertyList: installed, format: .xml, options: 0)
            .write(to: installedManifest)

        try seedStaging()
        let stagedManifest = root.appendingPathComponent(".build/production-package/manifest.plist")
        let staged = try plistDictionary(at: stagedManifest)
        let stagedSourceCommit = try XCTUnwrap(staged["SourceCommit"] as? String)
        let stagedVersion = try XCTUnwrap(staged["Version"] as? String)

        let output = try runScriptOutput("upgrade", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertTrue(output.contains("upgrade=provenance-updated acceptance=invalidated"), output)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist").path
        ))
        XCTAssertEqual(
            try XCTUnwrap(try plistDictionary(at: installedManifest)["SourceCommit"] as? String),
            stagedSourceCommit
        )
        XCTAssertEqual(
            try XCTUnwrap(try plistDictionary(at: installedManifest)["Version"] as? String),
            stagedVersion
        )
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
        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL)).mode, .disabled)
    }

    func testExplicitRollbackRestoresPreviousSetDisabledAndInvalidatesAcceptance() throws {
        let sandbox = root.appendingPathComponent(".build/production-maintenance-explicit-rollback-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        let previous = Data("rollback-previous".utf8)
        try previous.write(to: installedBinary)
        try synchronizeInstalledManifestChecksum(in: sandbox)
        try seedStaging()
        try runScript("upgrade", environment: ["MLM_TEST_ROOT": sandbox.path])
        _ = try runDeploymentLibrary(
            "record_deployment_acceptance deployment-dry-run pass",
            sandbox: sandbox
        )
        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        var enabled = try plistDictionary(at: configURL)
        enabled["Mode"] = "enabled"
        try PropertyListSerialization.data(fromPropertyList: enabled, format: .xml, options: 0).write(to: configURL)

        try runScript("rollback", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertEqual(try Data(contentsOf: installedBinary), previous)
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL)).mode, .disabled)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist").path
        ))
    }

    func testExplicitRollbackRejectsTamperedSlotBeforeMaintenanceMutation() throws {
        let sandbox = root.appendingPathComponent(".build/production-maintenance-tampered-rollback-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        try Data("rollback-original".utf8).write(to: installedBinary)
        try synchronizeInstalledManifestChecksum(in: sandbox)
        try seedStaging()
        try runScript("upgrade", environment: ["MLM_TEST_ROOT": sandbox.path])
        let support = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor")
        try Data("tampered".utf8).write(to: support.appendingPathComponent("rollback/macbook-lid-monitor-daemon"))
        let config = support.appendingPathComponent("config.plist")
        var enabled = try plistDictionary(at: config)
        enabled["Mode"] = "enabled"
        try PropertyListSerialization.data(fromPropertyList: enabled, format: .xml, options: 0).write(to: config)

        let failure = try runScriptFailure("rollback", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertTrue(failure.output.contains("rollback-set-invalid"), failure.output)
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: config)).mode, .enabled)
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
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        try Data("rollback-failure-old-payload".utf8).write(to: installedBinary)
        try synchronizeInstalledManifestChecksum(in: sandbox)
        try seedStaging()

        let failure = try runScriptFailure(
            "upgrade",
            environment: [
                "MLM_TEST_ROOT": sandbox.path,
                "MLM_FAIL_UPGRADE_STAGE": "rollback-restore",
            ]
        )
        XCTAssertTrue(failure.output.contains("job remains booted out"), failure.output)
    }

    func testInstalledSetLibraryDefinesStableSharedInterfaces() throws {
        let libraryURL = root.appendingPathComponent("scripts/lib/production-installed-set.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path))
        let text = try String(contentsOf: libraryURL, encoding: .utf8)
        for interface in [
            "verify_managed_metadata()",
            "normalized_config_sha256()",
            "verify_installed_set()",
            "installed_identity_lines()",
            "with_lifecycle_guard()",
        ] {
            XCTAssertTrue(text.contains(interface), interface)
        }
    }

    func testInstalledSetVerificationAcceptsModeOnlyChangeAndEmitsStableIdentity() throws {
        let sandbox = root.appendingPathComponent(".build/production-installed-set-valid-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        var config = try plistDictionary(at: configURL)
        config["Mode"] = "dry-run"
        try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0).write(to: configURL)

        let output = try runScriptOutput("installed-identity", environment: ["MLM_TEST_ROOT": sandbox.path])
        let keys = output.split(separator: "\n").map { String($0.split(separator: "=", maxSplits: 1)[0]) }
        XCTAssertEqual(keys, [
            "product", "version", "source_commit", "binary_sha256", "plist_sha256",
            "disabled_config_sha256", "hardware_profile", "binary_path", "plist_path",
            "config_path", "manifest_path", "sleep_authority_path", "acceptance_state_path",
            "health_state_path",
        ])
    }

    func testInstalledSetVerificationRejectsChecksumPolicyAndEnvironmentDrift() throws {
        let mutations: [(String, (URL) throws -> Void)] = [
            ("binary", { sandbox in
                try Data("drift".utf8).write(to: sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon"))
            }),
            ("plist", { sandbox in
                let url = sandbox.appendingPathComponent("Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist")
                var plist = try self.plistDictionary(at: url)
                plist["RunAtLoad"] = false
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
            }),
            ("config", { sandbox in
                let url = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
                var plist = try self.plistDictionary(at: url)
                plist["DebounceSeconds"] = 99
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
            }),
            ("environment", { sandbox in
                let url = sandbox.appendingPathComponent("Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist")
                var plist = try self.plistDictionary(at: url)
                plist["EnvironmentVariables"] = ["UNSAFE": "1"]
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
            }),
        ]

        for (name, mutate) in mutations {
            let sandbox = root.appendingPathComponent(".build/production-installed-set-drift-\(name)-root")
            try? FileManager.default.removeItem(at: sandbox)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            try seedStaging()
            try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
            try mutate(sandbox)
            let failure = try runScriptFailure("installed-identity", environment: ["MLM_TEST_ROOT": sandbox.path])
            XCTAssertTrue(failure.output.contains("error=installed-set-invalid"), "\(name): \(failure.output)")
        }
    }

    func testInstalledSetVerificationRejectsMetadataLinksAndUnsafeAncestors() throws {
        let variants = ["mode", "hardlink", "symlink", "ancestor"]
        for variant in variants {
            let sandbox = root.appendingPathComponent(".build/production-installed-set-metadata-\(variant)-root")
            try? FileManager.default.removeItem(at: sandbox)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            try seedStaging()
            try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
            let binary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
            switch variant {
            case "mode":
                try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: binary.path)
            case "hardlink":
                try FileManager.default.linkItem(at: binary, to: sandbox.appendingPathComponent("binary-alias"))
            case "symlink":
                let target = sandbox.appendingPathComponent("binary-target")
                try FileManager.default.moveItem(at: binary, to: target)
                try FileManager.default.createSymbolicLink(at: binary, withDestinationURL: target)
            case "ancestor":
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o777],
                    ofItemAtPath: sandbox.appendingPathComponent("Library/PrivilegedHelperTools").path
                )
            default:
                XCTFail("unknown variant")
            }
            let failure = try runScriptFailure("installed-identity", environment: ["MLM_TEST_ROOT": sandbox.path])
            XCTAssertTrue(failure.output.contains("error=installed-set-invalid"), "\(variant): \(failure.output)")
        }
    }

    func testLifecycleGuardRejectsConcurrentMutationBeforeManagedFilesChange() throws {
        let sandbox = root.appendingPathComponent(".build/production-lifecycle-guard-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()

        let first = Process()
        first.currentDirectoryURL = root
        first.executableURL = URL(fileURLWithPath: "/bin/bash")
        first.arguments = ["scripts/manage-production-daemon.sh", "install"]
        first.environment = ProcessInfo.processInfo.environment.merging([
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_HOLD_LIFECYCLE_GUARD_SECONDS": "3",
        ]) { _, new in new }
        first.standardOutput = FileHandle.nullDevice
        first.standardError = FileHandle.nullDevice
        try first.run()

        let guardURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/.lifecycle-guard")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: guardURL.path) {
            usleep(20_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: guardURL.path))
        let binary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        XCTAssertFalse(FileManager.default.fileExists(atPath: binary.path))

        let failure = try runScriptFailure("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        XCTAssertTrue(failure.output.contains("error=lifecycle-busy"), failure.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: binary.path))

        first.waitUntilExit()
        XCTAssertEqual(first.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: guardURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: binary.path))
    }

    func testLifecycleGuardCleansUpAfterSignalWithoutManagedMutation() throws {
        let sandbox = root.appendingPathComponent(".build/production-lifecycle-guard-signal-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()

        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/manage-production-daemon.sh", "install"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_HOLD_LIFECYCLE_GUARD_SECONDS": "30",
        ]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let guardURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/.lifecycle-guard")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: guardURL.path) {
            usleep(20_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: guardURL.path))

        process.terminate()
        process.waitUntilExit()

        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: guardURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon").path
        ))
    }

    func testManagedMetadataRejectsOwnerGroupAndTypeMismatch() throws {
        let sandbox = root.appendingPathComponent(".build/production-metadata-direct-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let file = sandbox.appendingPathComponent("file")
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        for arguments in [
            [file.path, "regular", "99999", String(getgid()), "644", "1"],
            [file.path, "regular", String(getuid()), "99999", "644", "1"],
            [file.path, "directory", String(getuid()), String(getgid()), "644", "1"],
        ] {
            let script = "export MLM_TEST_ROOT=\"$1\"; shift; source scripts/lib/production-package-common.sh; source scripts/lib/production-installed-set.sh; verify_managed_metadata \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\""
            let result = try commandResult("/bin/bash", ["-c", script, "metadata-test", sandbox.path] + arguments)
            XCTAssertNotEqual(result.status, 0, result.output)
            XCTAssertTrue(result.output.contains("error=installed-set-invalid"), result.output)
        }
    }

    func testLifecycleAndModeCommandIntegrationUsesRequiredBoundaries() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        for wrapper in [
            "install_package() { with_lifecycle_guard install_package_unlocked",
            "upgrade_package() { with_lifecycle_guard upgrade_package_unlocked",
            "rollback_upgrade() { with_lifecycle_guard rollback_upgrade_unlocked",
            "uninstall_package() { with_lifecycle_guard uninstall_package_unlocked",
        ] {
            XCTAssertTrue(text.contains(wrapper), wrapper)
        }
        XCTAssertTrue(text.contains("bootstrap_job() {\n    require_root_for_system\n    verify_installed_set"))
        XCTAssertTrue(text.contains("set_managed_mode() {"))
        XCTAssertTrue(text.contains("set_dry_run_mode() {\n    set_managed_mode dry-run"))
        XCTAssertTrue(text.contains("set_enabled_mode() {\n    set_managed_mode enabled"))
        XCTAssertFalse(text.contains("set_dry_run_mode() { with_lifecycle_guard"))
        XCTAssertFalse(text.contains("set_enabled_mode() { with_lifecycle_guard"))
    }

    func testLifecycleGuardTestHookCannotRunOutsideSandbox() throws {
        let library = try String(
            contentsOf: root.appendingPathComponent("scripts/lib/production-installed-set.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(library.contains("MLM_TEST_HOLD_LIFECYCLE_GUARD_SECONDS"))
        XCTAssertTrue(library.contains("[[ -n \"$SYSTEM_ROOT\" ]] || { printf 'error=test-hook-production-disabled"))
    }

    func testDeploymentStateLibraryDefinesStableInterfacesAndPrivacyBoundary() throws {
        let url = root.appendingPathComponent("scripts/lib/production-deployment-state.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let text = try String(contentsOf: url, encoding: .utf8)
        for interface in [
            "target_hardware_identity_lines()",
            "deployment_identity_lines()",
            "record_deployment_acceptance()",
            "verify_deployment_acceptance()",
            "invalidate_deployment_acceptance()",
            "write_deployment_reboot_state()",
            "verify_deployment_reboot_state()",
        ] {
            XCTAssertTrue(text.contains(interface), interface)
        }
        for prohibited in ["serial", "uuid", "udid", "raw_report", "ioreg"] {
            XCTAssertFalse(text.lowercased().contains(prohibited), prohibited)
        }
    }

    func testDeploymentIdentityRejectsModelAndChipMismatch() throws {
        let sandbox = root.appendingPathComponent(".build/production-deployment-target-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        for override in [
            ["MLM_TEST_TARGET_MODEL": "MacBookPro99,9"],
            ["MLM_TEST_TARGET_CHIP": "Unknown Chip"],
        ] {
            let result = try runDeploymentLibrary(
                "deployment_identity_lines",
                sandbox: sandbox,
                environment: override
            )
            XCTAssertNotEqual(result.status, 0, result.output)
            XCTAssertTrue(result.output.contains("error=target-hardware-invalid"), result.output)
        }
    }

    func testDeploymentAcceptanceIsAtomicCompleteAndIdentityBound() throws {
        let sandbox = root.appendingPathComponent(".build/production-deployment-acceptance-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        _ = try runDeploymentLibrary(
            "record_deployment_acceptance deployment-dry-run pass",
            sandbox: sandbox
        )
        let partial = try runDeploymentLibrary(
            "verify_deployment_acceptance deployment-dry-run deployment-enabled-once",
            sandbox: sandbox
        )
        XCTAssertNotEqual(partial.status, 0, partial.output)

        _ = try runDeploymentLibrary(
            "record_deployment_acceptance deployment-enabled-once pass",
            sandbox: sandbox
        )
        let complete = try runDeploymentLibrary(
            "verify_deployment_acceptance deployment-dry-run deployment-enabled-once",
            sandbox: sandbox
        )
        XCTAssertEqual(complete.status, 0, complete.output)

        let acceptance = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist")
        let attributes = try FileManager.default.attributesOfItem(atPath: acceptance.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: acceptance.path + ".tmp"))

        let binary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        try Data("identity-drift".utf8).write(to: binary)
        let stale = try runDeploymentLibrary(
            "verify_deployment_acceptance deployment-dry-run deployment-enabled-once",
            sandbox: sandbox
        )
        XCTAssertNotEqual(stale.status, 0, stale.output)
        XCTAssertTrue(stale.output.contains("error=deployment-acceptance-invalid"), stale.output)
    }

    func testLifecycleReplacementInvalidatesDeploymentAcceptance() throws {
        let sandbox = root.appendingPathComponent(".build/production-deployment-invalidation-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let acceptance = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist")

        _ = try runDeploymentLibrary("record_deployment_acceptance deployment-dry-run pass", sandbox: sandbox)
        XCTAssertTrue(FileManager.default.fileExists(atPath: acceptance.path))
        let installedBinary = sandbox.appendingPathComponent("Library/PrivilegedHelperTools/macbook-lid-monitor-daemon")
        try Data("lifecycle-previous-payload".utf8).write(to: installedBinary)
        try synchronizeInstalledManifestChecksum(in: sandbox)
        try seedStaging()
        try runScript("upgrade", environment: ["MLM_TEST_ROOT": sandbox.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: acceptance.path))

        _ = try runDeploymentLibrary("record_deployment_acceptance deployment-dry-run pass", sandbox: sandbox)
        try runScript("rollback", environment: ["MLM_TEST_ROOT": sandbox.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: acceptance.path))
    }

    func testInitialInstallInvalidatesPreexistingDeploymentState() throws {
        let sandbox = root.appendingPathComponent(".build/production-deployment-install-invalidation-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let support = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let acceptance = support.appendingPathComponent("deployment-acceptance.plist")
        let reboot = support.appendingPathComponent("deployment-reboot.plist")
        try Data("stale".utf8).write(to: acceptance)
        try Data("stale".utf8).write(to: reboot)

        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        XCTAssertFalse(FileManager.default.fileExists(atPath: acceptance.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reboot.path))
    }

    func testDeploymentRebootStateRequiresChangedBootAndMatchingIdentity() throws {
        let sandbox = root.appendingPathComponent(".build/production-deployment-reboot-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        _ = try runDeploymentLibrary("write_deployment_reboot_state 1700000000", sandbox: sandbox)
        let unchanged = try runDeploymentLibrary(
            "verify_deployment_reboot_state",
            sandbox: sandbox,
            environment: ["MLM_TEST_BOOT_EPOCH": "1700000000"]
        )
        XCTAssertNotEqual(unchanged.status, 0, unchanged.output)

        let changed = try runDeploymentLibrary(
            "verify_deployment_reboot_state",
            sandbox: sandbox,
            environment: ["MLM_TEST_BOOT_EPOCH": "1700000100"]
        )
        XCTAssertEqual(changed.status, 0, changed.output)
    }

    func testDeploymentTestHooksAreSandboxOnly() throws {
        let manager = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        let deployment = try String(
            contentsOf: root.appendingPathComponent("scripts/lib/production-deployment-state.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(manager.contains("error=test-hook-production-disabled reason=boot-epoch"))
        XCTAssertTrue(manager.contains("error=test-hook-production-disabled reason=state-mtime"))
        XCTAssertTrue(manager.contains("error=test-hook-production-disabled reason=activation-bootstrap"))
        XCTAssertTrue(deployment.contains("test-hook-production-disabled target-model"))
        XCTAssertTrue(deployment.contains("test-hook-production-disabled target-chip"))
        XCTAssertTrue(deployment.contains("test-hook-production-disabled boot-epoch"))
    }

    func testObservabilityLibraryDefinesStableReadOnlyInterfaces() throws {
        let url = root.appendingPathComponent("scripts/lib/production-observability.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let text = try String(contentsOf: url, encoding: .utf8)
        for interface in [
            "status_job()",
            "diagnostics()",
            "crash_budget_status_lines()",
            "process_metric_lines()",
            "health_status_lines()",
            "log_status_lines()",
            "operational_baseline()",
        ] {
            XCTAssertTrue(text.contains(interface), interface)
        }
        XCTAssertFalse(text.contains("tail "))
        XCTAssertFalse(text.contains("cat \"$MANAGED_STDOUT_LOG\""))
        XCTAssertFalse(text.contains("cat \"$MANAGED_STDERR_LOG\""))
    }

    func testStatusAndDiagnosticsEmitStableParserFriendlyFields() throws {
        let sandbox = root.appendingPathComponent(".build/production-observability-status-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let support = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor")
        let logs = sandbox.appendingPathComponent("Library/Logs/MacBookLidMonitor")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("log-data".utf8).write(to: logs.appendingPathComponent("production.log"))
        try Data("{\"unexpectedExitTimes\":[],\"circuitOpen\":false,\"runActive\":true}".utf8)
            .write(to: support.appendingPathComponent("crash-budget.json"))
        try writeHealthFixture(
            at: support.appendingPathComponent("health.plist"),
            state: "monitoring-armed"
        )

        let environment = [
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_JOB_STATE": "loaded",
            "MLM_TEST_PROCESS_IDS": "4242",
            "MLM_TEST_PROCESS_METRICS": "elapsed=120 cpu=0.2 rss=4096 vsz=8192",
        ]
        let status = try runScriptOutput("status", environment: environment)
        for key in [
            "installed=true", "version=", "source_commit=", "mode=disabled", "job=loaded",
            "process_count=1", "health_state=monitoring-armed", "hardware_model=MacBookPro18,1",
            "hardware_chip=Apple M1 Pro", "integrity=valid", "crash_state=closed",
            "acceptance_state=missing", "lease_state=present",
        ] {
            XCTAssertTrue(status.contains(key), "\(key) in \(status)")
        }
        let diagnostics = try runScriptOutput("diagnostics", environment: environment)
        for key in ["pid=4242", "elapsed=120", "cpu=0.2", "rss=4096", "vsz=8192", "log_path="] {
            XCTAssertTrue(diagnostics.contains(key), "\(key) in \(diagnostics)")
        }
        XCTAssertFalse(diagnostics.contains("log-data"))
    }

    func testObservabilityReportsMissingAndCorruptStateStably() throws {
        let sandbox = root.appendingPathComponent(".build/production-observability-corrupt-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        let support = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor")

        let missing = try runScriptOutput("diagnostics", environment: ["MLM_TEST_ROOT": sandbox.path])
        XCTAssertTrue(missing.contains("health_state=unavailable"), missing)
        XCTAssertTrue(missing.contains("crash_state=unavailable"), missing)

        try Data("not-json".utf8).write(to: support.appendingPathComponent("health.plist"))
        try Data("not-json".utf8).write(to: support.appendingPathComponent("crash-budget.json"))
        let corrupt = try runScriptOutput("diagnostics", environment: ["MLM_TEST_ROOT": sandbox.path])
        XCTAssertTrue(corrupt.contains("health_state=corrupt"), corrupt)
        XCTAssertTrue(corrupt.contains("crash_state=corrupt"), corrupt)
    }

    func testObservabilityReportsPartialDeploymentAcceptanceWithoutCallingItCorrupt() throws {
        let sandbox = root.appendingPathComponent(".build/production-observability-partial-acceptance-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])

        _ = try runDeploymentLibrary(
            "record_deployment_acceptance deployment-dry-run pass",
            sandbox: sandbox
        )

        let status = try runScriptOutput("status", environment: ["MLM_TEST_ROOT": sandbox.path])
        XCTAssertTrue(status.contains("acceptance_state=partial"), status)
        XCTAssertFalse(status.contains("acceptance_state=corrupt"), status)
    }

    func testOperationalBaselineRequiresCompleteHealthyEnabledEvidence() throws {
        let sandbox = root.appendingPathComponent(".build/production-operational-baseline-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])

        let incomplete = try runScriptFailure("operational-baseline", environment: [
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_JOB_STATE": "loaded",
            "MLM_TEST_PROCESS_IDS": "4242",
        ])
        XCTAssertTrue(incomplete.output.contains("error=operational-baseline-invalid"), incomplete.output)

        try runScript("deployment-dry-run", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("deployment-enabled-once", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("deployment-recovery-resleep", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("activate", environment: ["MLM_TEST_ROOT": sandbox.path])
        let health = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/health.plist")
        try writeHealthFixture(at: health, state: "monitoring-armed", mode: "enabled", pid: 4242)

        let output = try runScriptOutput("operational-baseline", environment: [
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_JOB_STATE": "loaded",
            "MLM_TEST_PROCESS_IDS": "4242",
            "MLM_TEST_PROCESS_METRICS": "elapsed=120 cpu=0.2 rss=4096 vsz=8192",
        ])
        XCTAssertTrue(output.contains("operational_baseline=pass"), output)
    }

    func testOperationalBaselineRejectsStaleOrUnsafeHealthSnapshot() throws {
        let sandbox = root.appendingPathComponent(".build/production-operational-baseline-health-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        for command in ["deployment-dry-run", "deployment-enabled-once", "deployment-recovery-resleep"] {
            try runScript(command, environment: ["MLM_TEST_ROOT": sandbox.path])
        }
        try runScript("activate", environment: ["MLM_TEST_ROOT": sandbox.path])
        let health = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/health.plist")
        try writeHealthFixture(
            at: health,
            state: "monitoring-armed",
            mode: "enabled",
            pid: 4242,
            updatedAt: Date(timeIntervalSinceNow: -600)
        )
        let environment = [
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_JOB_STATE": "loaded",
            "MLM_TEST_PROCESS_IDS": "4242",
        ]
        let stale = try runScriptFailure("operational-baseline", environment: environment)
        XCTAssertTrue(stale.output.contains("reason=health"), stale.output)

        try writeHealthFixture(at: health, state: "monitoring-armed", mode: "enabled", pid: 4242)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: health.path)
        let unsafe = try runScriptFailure("operational-baseline", environment: environment)
        XCTAssertTrue(unsafe.output.contains("reason=health"), unsafe.output)
    }

    func testBoundedDeploymentCommandsRecordAcceptanceAndReturnDisabled() throws {
        let sandbox = root.appendingPathComponent(".build/production-bounded-deployment-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")

        for command in ["deployment-dry-run", "deployment-enabled-once", "deployment-recovery-resleep"] {
            try runScript(command, environment: ["MLM_TEST_ROOT": sandbox.path])
            XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL)).mode, .disabled)
        }

        let verified = try runDeploymentLibrary(
            "verify_deployment_acceptance deployment-dry-run deployment-enabled-once deployment-recovery-resleep",
            sandbox: sandbox
        )
        XCTAssertEqual(verified.status, 0, verified.output)
    }

    func testActivationRejectsPartialOrCorruptAcceptanceAndPreservesDisabled() throws {
        for variant in ["partial", "corrupt"] {
            let sandbox = root.appendingPathComponent(".build/production-activation-\(variant)-root")
            try? FileManager.default.removeItem(at: sandbox)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            try seedStaging()
            try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
            try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
            try runScript("deployment-dry-run", environment: ["MLM_TEST_ROOT": sandbox.path])
            if variant == "corrupt" {
                let acceptance = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist")
                try Data("corrupt".utf8).write(to: acceptance)
            }

            let failure = try runScriptFailure("activate", environment: ["MLM_TEST_ROOT": sandbox.path])
            XCTAssertTrue(failure.output.contains("deployment-acceptance-invalid"), failure.output)
            let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
            XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL)).mode, .disabled)
        }
    }

    func testActivationLeavesEnabledOnlyAfterCompleteMatchingAcceptance() throws {
        let sandbox = root.appendingPathComponent(".build/production-activation-complete-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        for command in ["deployment-dry-run", "deployment-enabled-once", "deployment-recovery-resleep"] {
            try runScript(command, environment: ["MLM_TEST_ROOT": sandbox.path])
        }

        try runScript("activate", environment: ["MLM_TEST_ROOT": sandbox.path])

        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL)).mode, .enabled)
    }

    func testActivationBootstrapFailureRestoresDisabled() throws {
        let sandbox = root.appendingPathComponent(".build/production-activation-bootstrap-failure-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        for stage in ["deployment-dry-run", "deployment-enabled-once", "deployment-recovery-resleep"] {
            _ = try runDeploymentLibrary("record_deployment_acceptance \(stage) pass", sandbox: sandbox)
        }

        let failure = try runScriptFailure(
            "activate",
            environment: [
                "MLM_TEST_ROOT": sandbox.path,
                "MLM_TEST_ACTIVATION_BOOTSTRAP_FAIL": "1",
            ]
        )

        XCTAssertTrue(failure.output.contains("activation bootstrap failed"), failure.output)
        let configURL = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        XCTAssertEqual(
            try ProductionConfigurationDecoder().decode(Data(contentsOf: configURL)).mode,
            .disabled
        )
    }

    func testBoundedDeploymentInjectedFailureAndSignalRestoreDisabled() throws {
        let failureRoot = root.appendingPathComponent(".build/production-bounded-failure-root")
        try? FileManager.default.removeItem(at: failureRoot)
        defer { try? FileManager.default.removeItem(at: failureRoot) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": failureRoot.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": failureRoot.path])
        _ = try runScriptFailure("deployment-dry-run", environment: [
            "MLM_TEST_ROOT": failureRoot.path,
            "MLM_TEST_DEPLOYMENT_FAIL_STAGE": "dry-run",
        ])
        let failureConfig = failureRoot.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: failureConfig)).mode, .disabled)

        let signalRoot = root.appendingPathComponent(".build/production-bounded-signal-root")
        try? FileManager.default.removeItem(at: signalRoot)
        defer { try? FileManager.default.removeItem(at: signalRoot) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": signalRoot.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": signalRoot.path])
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/manage-production-daemon.sh", "deployment-dry-run"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "MLM_TEST_ROOT": signalRoot.path,
            "MLM_TEST_DEPLOYMENT_HOLD_SECONDS": "30",
        ]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let signalConfig = signalRoot.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        for _ in 0..<150 {
            if let data = try? Data(contentsOf: signalConfig),
               let decoded = try? ProductionConfigurationDecoder().decode(data),
               decoded.mode == .dryRun { break }
            usleep(20_000)
        }
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: signalConfig)).mode, .dryRun)
        process.terminate()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: signalConfig)).mode, .disabled)
    }

    func testDeploymentDispatcherHasStableCommandsAndNoUnrestrictedEnable() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("deployment-dry-run) deployment_dry_run"))
        XCTAssertTrue(text.contains("deployment-enabled-once) deployment_enabled_once"))
        XCTAssertTrue(text.contains("deployment-recovery-resleep) deployment_recovery_resleep"))
        XCTAssertTrue(text.contains("activate) activate_deployment"))
        XCTAssertFalse(text.contains("enable)"))
        XCTAssertTrue(text.contains("set_managed_mode()"))
        XCTAssertTrue(text.contains("MLM_TEST_DEPLOYMENT_FAIL_STAGE"))
        XCTAssertTrue(text.contains("error=test-hook-production-disabled reason=deployment"))
    }

    func testDeploymentRebootCommandsAreStableAndCannotUseHistoricalDestructiveFlow() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent("scripts/manage-production-daemon.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("deployment-reboot-start) deployment_reboot_start"))
        XCTAssertTrue(text.contains("deployment-reboot-finish) deployment_reboot_finish"))
        let start = try XCTUnwrap(text.range(of: "deployment_reboot_start()"))
        let finish = try XCTUnwrap(text.range(of: "deployment_reboot_finish()"))
        let end = try XCTUnwrap(text.range(of: "uninstall_package_unlocked()"))
        let body = String(text[start.lowerBound..<end.lowerBound])
        for prohibited in ["accept_task14_reboot", "upgrade_package", "rollback_upgrade", "uninstall_package", "disable_job", "pmset", "shutdown", "reboot -"] {
            XCTAssertFalse(body.contains(prohibited), prohibited)
        }
        XCTAssertLessThan(start.lowerBound, finish.lowerBound)
    }

    func testDeploymentRebootStartFinishPreservesEnabledAndCleansTemporaryArtifacts() throws {
        let sandbox = root.appendingPathComponent(".build/production-enabled-reboot-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        for command in ["deployment-dry-run", "deployment-enabled-once", "deployment-recovery-resleep"] {
            try runScript(command, environment: ["MLM_TEST_ROOT": sandbox.path])
        }
        try runScript("activate", environment: ["MLM_TEST_ROOT": sandbox.path])
        let health = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/health.plist")
        try writeHealthFixture(at: health, state: "monitoring-armed", mode: "enabled", pid: 4242)
        let base = [
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_JOB_STATE": "loaded",
            "MLM_TEST_PROCESS_IDS": "4242",
            "MLM_TEST_BOOT_EPOCH": "100",
        ]
        try runScript("deployment-reboot-start", environment: base)
        let support = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor")
        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("deployment-reboot.plist").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("reboot-observer-evidence.plist").path))

        var finish = base
        finish["MLM_TEST_BOOT_EPOCH"] = "200"
        finish["MLM_TEST_REBOOT_OBSERVER_CONSOLE_USER"] = "root"
        try runScript("deployment-reboot-finish", environment: finish)

        let config = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: config)).mode, .enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("deployment-reboot.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("reboot-observer-evidence.plist").path))
    }

    func testDeploymentRebootFinishRejectsUnchangedBootWithoutDisabling() throws {
        let sandbox = root.appendingPathComponent(".build/production-enabled-reboot-same-boot-root")
        try? FileManager.default.removeItem(at: sandbox)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try seedStaging()
        try runScript("install", environment: ["MLM_TEST_ROOT": sandbox.path])
        try runScript("bootstrap", environment: ["MLM_TEST_ROOT": sandbox.path])
        for command in ["deployment-dry-run", "deployment-enabled-once", "deployment-recovery-resleep"] {
            try runScript(command, environment: ["MLM_TEST_ROOT": sandbox.path])
        }
        try runScript("activate", environment: ["MLM_TEST_ROOT": sandbox.path])
        let health = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/health.plist")
        try writeHealthFixture(at: health, state: "monitoring-armed", mode: "enabled", pid: 4242)
        let environment = [
            "MLM_TEST_ROOT": sandbox.path,
            "MLM_TEST_JOB_STATE": "loaded",
            "MLM_TEST_PROCESS_IDS": "4242",
            "MLM_TEST_BOOT_EPOCH": "100",
        ]
        try runScript("deployment-reboot-start", environment: environment)
        let failure = try runScriptFailure("deployment-reboot-finish", environment: environment)
        XCTAssertTrue(failure.output.contains("reboot-not-detected"), failure.output)
        let config = sandbox.appendingPathComponent("Library/Application Support/MacBookLidMonitor/config.plist")
        XCTAssertEqual(try ProductionConfigurationDecoder().decode(Data(contentsOf: config)).mode, .enabled)
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
        manifest["SourceCommit"] = try commandOutput("/usr/bin/git", ["rev-parse", "HEAD"])
        manifest["BinarySHA256"] = try commandOutput("/usr/bin/shasum", ["-a", "256", binary.path])
            .split(separator: " ").first.map(String.init)
        let stagedPlist = staging.appendingPathComponent("com.crazydennies.macbook-lid-monitor.plist")
        let stagedConfig = staging.appendingPathComponent("config.plist")
        manifest["PlistSHA256"] = try commandOutput(
            "/usr/bin/shasum", ["-a", "256", stagedPlist.path]
        ).split(separator: " ").first.map(String.init)
        manifest["DisabledConfigSHA256"] = try normalizedConfigChecksum(stagedConfig)
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

    private func commandResult(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func runDeploymentLibrary(
        _ command: String,
        sandbox: URL,
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let script = "source scripts/lib/production-package-common.sh; source scripts/lib/production-installed-set.sh; source scripts/lib/production-deployment-state.sh; \(command)"
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["MLM_TEST_ROOT": sandbox.path].merging(environment) { _, new in new }
        ) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func normalizedConfigChecksum(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var object = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        object["Mode"] = "disabled"
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return ProductionSHA256Hasher().hash(canonical)
    }

    private func writeHealthFixture(
        at url: URL,
        state: String,
        mode: String = "disabled",
        pid: Int = 4242,
        updatedAt: Date = Date()
    ) throws {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: updatedAt)
        let value: [String: Any] = [
            "schemaVersion": 1,
            "version": "test",
            "mode": mode,
            "profileID": "m1-pro-0x8104-report-id-1-v1",
            "state": state,
            "pid": pid,
            "lastTransitionTime": timestamp,
            "lastValidSampleTime": timestamp,
            "updatedAt": timestamp,
        ]
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func runScript(_ command: String, environment: [String: String] = [:]) throws {
        let result = try runScriptResult(command, environment: environment)
        guard result.status == 0 else {
            throw NSError(
                domain: "ProductionManagementScriptTests",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: result.output]
            )
        }
    }

    private func runScriptOutput(_ command: String, environment: [String: String] = [:]) throws -> String {
        let result = try runScriptResult(command, environment: environment)
        guard result.status == 0 else {
            throw NSError(
                domain: "ProductionManagementScriptTests",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: result.output]
            )
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runScriptFailure(_ command: String, environment: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let result = try runScriptResult(command, environment: environment)
        XCTAssertNotEqual(result.status, 0, result.output)
        return result
    }

    private func runScriptResult(_ command: String, environment: [String: String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/manage-production-daemon.sh", command]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }
}
