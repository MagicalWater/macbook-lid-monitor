import XCTest
@testable import LidMonitor

final class AutoSleepCLIParserTests: XCTestCase {
    func testDryRunUsesCalibratedDefaults() throws {
        let options = try CLIParser.parse(["--auto-sleep", "--dry-run"])

        XCTAssertEqual(
            options.mode,
            .autoSleep(.dryRun, .calibratedDefault)
        )
        XCTAssertFalse(options.includeRaw)
        XCTAssertNil(options.duration)
    }

    func testAutoSleepRequiresExecutionMode() {
        XCTAssertThrowsError(try CLIParser.parse(["--auto-sleep"]))
    }

    func testExecutionModeRequiresAutoSleep() {
        XCTAssertThrowsError(try CLIParser.parse(["--execute-sleep"]))
        XCTAssertThrowsError(try CLIParser.parse(["--dry-run"]))
    }

    func testDryRunAndExecuteSleepConflict() {
        XCTAssertThrowsError(
            try CLIParser.parse([
                "--auto-sleep", "--dry-run", "--execute-sleep"
            ])
        )
    }

    func testAutoSleepRejectsDiagnosticFlags() {
        XCTAssertThrowsError(
            try CLIParser.parse(["--auto-sleep", "--dry-run", "--raw"])
        )
        XCTAssertThrowsError(
            try CLIParser.parse([
                "--auto-sleep", "--dry-run", "--duration", "10"
            ])
        )
        XCTAssertThrowsError(
            try CLIParser.parse(["--watch", "--auto-sleep", "--dry-run"])
        )
    }

    func testCustomPolicyIsParsed() throws {
        let options = try CLIParser.parse([
            "--auto-sleep", "--dry-run",
            "--sleep-threshold", "59",
            "--reopen-threshold", "72",
            "--debounce", "2.5",
            "--startup-cooldown", "6",
            "--wake-recovery", "18"
        ])

        XCTAssertEqual(
            options.mode,
            .autoSleep(
                .dryRun,
                try LidSleepPolicy(
                    sleepThreshold: 59,
                    reopenThreshold: 72,
                    closeDebounce: 2.5,
                    startupCooldown: 6,
                    wakeRecovery: 18
                )
            )
        )
    }

    func testCalibratedDefaultsSplitStartupAndWakeRecovery() {
        XCTAssertEqual(LidSleepPolicy.calibratedDefault.closeDebounce, 2)
        XCTAssertEqual(LidSleepPolicy.calibratedDefault.startupCooldown, 5)
        XCTAssertEqual(LidSleepPolicy.calibratedDefault.wakeRecovery, 15)
    }

    func testObsoleteWakeCooldownIsRejectedWithMigrationError() {
        XCTAssertThrowsError(
            try CLIParser.parse([
                "--auto-sleep", "--dry-run", "--wake-cooldown", "5"
            ])
        ) { error in
            XCTAssertEqual(
                error as? CLIParseError,
                .obsoleteWakeCooldownOption
            )
        }
    }

    func testThresholdsMustBeWithinSensorRange() {
        for value in ["-1", "361"] {
            XCTAssertThrowsError(
                try CLIParser.parse([
                    "--auto-sleep", "--dry-run",
                    "--sleep-threshold", value
                ])
            )
            XCTAssertThrowsError(
                try CLIParser.parse([
                    "--auto-sleep", "--dry-run",
                    "--reopen-threshold", value
                ])
            )
        }
    }

    func testReopenThresholdMustExceedSleepThreshold() {
        XCTAssertThrowsError(
            try CLIParser.parse([
                "--auto-sleep", "--dry-run",
                "--sleep-threshold", "70",
                "--reopen-threshold", "60"
            ])
        )
        XCTAssertThrowsError(
            try CLIParser.parse([
                "--auto-sleep", "--dry-run",
                "--sleep-threshold", "60",
                "--reopen-threshold", "60"
            ])
        )
    }

    func testCloseDebounceMustBePositiveAndFinite() {
        for value in ["0", "-1", "nan", "inf"] {
            XCTAssertThrowsError(
                try CLIParser.parse([
                    "--auto-sleep", "--dry-run",
                    "--debounce", value
                ])
            )
        }
    }

    func testStartupCooldownMustBeNonnegativeAndFinite() throws {
        XCTAssertNoThrow(
            try CLIParser.parse([
                "--auto-sleep", "--dry-run",
                "--startup-cooldown", "0"
            ])
        )

        for value in ["-1", "nan", "inf"] {
            XCTAssertThrowsError(
                try CLIParser.parse([
                    "--auto-sleep", "--dry-run",
                    "--startup-cooldown", value
                ])
            )
        }
    }

    func testWakeRecoveryMustBePositiveAndFinite() {
        for value in ["0", "-1", "nan", "inf"] {
            XCTAssertThrowsError(
                try CLIParser.parse([
                    "--auto-sleep", "--dry-run",
                    "--wake-recovery", value
                ])
            )
        }
    }

    func testPolicyOptionsRequireValues() {
        for option in [
            "--sleep-threshold",
            "--reopen-threshold",
            "--debounce",
            "--startup-cooldown",
            "--wake-recovery"
        ] {
            XCTAssertThrowsError(
                try CLIParser.parse(["--auto-sleep", "--dry-run", option])
            )
        }
    }
}
