import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionConfigurationTests: XCTestCase {
    func testDecodesDisabledDryRunAndEnabledModes() throws {
        for (raw, expected) in [
            ("disabled", ProductionMode.disabled),
            ("dry-run", ProductionMode.dryRun),
            ("enabled", ProductionMode.enabled),
        ] {
            let configuration = try ProductionConfigurationDecoder().decode(
                plist(mode: raw)
            )
            XCTAssertEqual(configuration.mode, expected)
            XCTAssertEqual(configuration.policy, .calibratedDefault)
            XCTAssertEqual(configuration.hardwareProfileID, "m1-pro-0x8104-report-id-1-v1")
        }
    }

    func testRejectsUnsupportedSchemaAndUnknownKey() {
        XCTAssertThrowsError(
            try ProductionConfigurationDecoder().decode(plist(schemaVersion: 2))
        ) { error in
            XCTAssertEqual(error as? ProductionConfigurationError, .unsupportedSchemaVersion(2))
        }

        var value = dictionary()
        value["ExecuteSleep"] = true
        XCTAssertThrowsError(try ProductionConfigurationDecoder().decode(encode(value))) { error in
            XCTAssertEqual(error as? ProductionConfigurationError, .unsupportedKey("ExecuteSleep"))
        }
    }

    func testRejectsMissingModeAndUnsupportedMode() {
        var missing = dictionary()
        missing.removeValue(forKey: "Mode")
        XCTAssertThrowsError(try ProductionConfigurationDecoder().decode(encode(missing))) { error in
            XCTAssertEqual(error as? ProductionConfigurationError, .missingField("Mode"))
        }

        XCTAssertThrowsError(
            try ProductionConfigurationDecoder().decode(plist(mode: "execute-sleep"))
        ) { error in
            XCTAssertEqual(error as? ProductionConfigurationError, .unsupportedMode("execute-sleep"))
        }
    }

    func testRejectsUnsafePolicy() {
        var value = dictionary()
        value["SleepThreshold"] = 80
        value["ReopenThreshold"] = 75
        XCTAssertThrowsError(try ProductionConfigurationDecoder().decode(encode(value))) { error in
            XCTAssertEqual(error as? ProductionConfigurationError, .invalidPolicy("invalid-threshold-relationship"))
        }
    }

    func testRejectsBlankHardwareProfileID() {
        var value = dictionary()
        value["HardwareProfileID"] = "  "
        XCTAssertThrowsError(try ProductionConfigurationDecoder().decode(encode(value))) { error in
            XCTAssertEqual(error as? ProductionConfigurationError, .invalidHardwareProfileID)
        }
    }

    func testLoaderUsesFixedPathAndRequiresRootOwnedNonWritableFile() throws {
        let reader = FakeProductionConfigurationReader(
            data: plist(mode: "dry-run"),
            metadata: .init(ownerID: 0, groupID: 0, permissions: 0o644, isRegularFile: true, isSymbolicLink: false)
        )
        let loader = ProductionConfigurationLoader(reader: reader)

        let result = try loader.load()

        XCTAssertEqual(reader.requestedPaths, [ProductionConfigurationLoader.fixedPath])
        XCTAssertEqual(result.mode, .dryRun)
    }

    func testLoaderRejectsSymlinkWrongOwnerAndWritableConfiguration() {
        let invalid: [(ProductionFileMetadata, ProductionConfigurationError)] = [
            (.init(ownerID: 0, groupID: 0, permissions: 0o644, isRegularFile: true, isSymbolicLink: true), .configurationIsSymbolicLink),
            (.init(ownerID: 501, groupID: 20, permissions: 0o644, isRegularFile: true, isSymbolicLink: false), .invalidConfigurationOwner(501)),
            (.init(ownerID: 0, groupID: 20, permissions: 0o644, isRegularFile: true, isSymbolicLink: false), .invalidConfigurationGroup(20)),
            (.init(ownerID: 0, groupID: 0, permissions: 0o666, isRegularFile: true, isSymbolicLink: false), .unsafeConfigurationPermissions(0o666)),
        ]

        for (metadata, expected) in invalid {
            let loader = ProductionConfigurationLoader(
                reader: FakeProductionConfigurationReader(data: plist(), metadata: metadata)
            )
            XCTAssertThrowsError(try loader.load()) { error in
                XCTAssertEqual(error as? ProductionConfigurationError, expected)
            }
        }
    }

    private func plist(
        schemaVersion: Int = 1,
        mode: String = "disabled"
    ) -> Data {
        encode(dictionary(schemaVersion: schemaVersion, mode: mode))
    }

    private func dictionary(
        schemaVersion: Int = 1,
        mode: String = "disabled"
    ) -> [String: Any] {
        [
            "SchemaVersion": schemaVersion,
            "Mode": mode,
            "HardwareProfileID": "m1-pro-0x8104-report-id-1-v1",
            "SleepThreshold": 68,
            "ReopenThreshold": 75,
            "CloseDebounceSeconds": 2.0,
            "StartupCooldownSeconds": 5.0,
            "WakeRecoverySeconds": 15.0,
        ]
    }

    private func encode(_ dictionary: [String: Any]) -> Data {
        try! PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
    }
}

private final class FakeProductionConfigurationReader: ProductionConfigurationReading, @unchecked Sendable {
    let data: Data
    let metadata: ProductionFileMetadata
    private(set) var requestedPaths: [String] = []

    init(data: Data, metadata: ProductionFileMetadata) {
        self.data = data
        self.metadata = metadata
    }

    func read(path: String) throws -> (Data, ProductionFileMetadata) {
        requestedPaths.append(path)
        return (data, metadata)
    }
}
