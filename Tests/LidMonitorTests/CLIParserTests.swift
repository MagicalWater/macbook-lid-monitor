import XCTest
@testable import LidMonitorCore

final class CLIParserTests: XCTestCase {
    func testNoArgumentsDefaultsToWatch() throws {
        XCTAssertEqual(
            try CLIParser.parse([]),
            CLIOptions(mode: .watch, includeRaw: false, duration: nil)
        )
    }

    func testListModeRejectsRaw() {
        XCTAssertThrowsError(try CLIParser.parse(["--list", "--raw"])) { error in
            XCTAssertEqual(error as? CLIParseError, .rawRequiresWatch)
        }
    }

    func testConflictingModesAreRejected() {
        XCTAssertThrowsError(try CLIParser.parse(["--list", "--watch"])) { error in
            XCTAssertEqual(error as? CLIParseError, .conflictingModes)
        }
    }

    func testDurationMustBePositiveFiniteNumber() {
        for value in ["0", "-1", "nan", "inf"] {
            XCTAssertThrowsError(try CLIParser.parse(["--duration", value]))
        }
    }

    func testMissingDurationValueIsRejected() {
        XCTAssertThrowsError(try CLIParser.parse(["--duration"])) { error in
            XCTAssertEqual(error as? CLIParseError, .missingDurationValue)
        }
    }

    func testUnknownOptionIsRejected() {
        XCTAssertThrowsError(try CLIParser.parse(["--unknown"])) { error in
            XCTAssertEqual(error as? CLIParseError, .unknownOption("--unknown"))
        }
    }
    func testCLIEntryPointMapsInvalidArgumentsToUsage() {
        let result = LidMonitorCLIEntryPoint.run(arguments: ["--definitely-invalid"])
        XCTAssertEqual(result, ExitCode.usage.rawValue)
    }

}
