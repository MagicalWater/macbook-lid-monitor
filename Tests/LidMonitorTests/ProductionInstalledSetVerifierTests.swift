import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionInstalledSetVerifierTests: XCTestCase {
    func testValidInstalledSetReturnsIdentity() throws {
        let fixture = try Fixture()
        let identity = try fixture.verifier.verify(mode: .enabled)
        XCTAssertEqual(identity.sourceCommit, fixture.sourceCommit)
        XCTAssertEqual(identity.hardwareProfileID, fixture.profileID)
    }

    func testModeOnlyConfigChangeNormalizesToDisabledTemplate() throws {
        let fixture = try Fixture(mode: "enabled")
        XCTAssertNoThrow(try fixture.verifier.verify(mode: .enabled))
    }

    func testNonModeConfigDriftIsRejected() throws {
        let fixture = try Fixture(configMutation: { $0["SleepThreshold"] = 42 })
        XCTAssertThrowsError(try fixture.verifier.verify(mode: .enabled))
    }

    func testBinaryPlistAndManifestMismatchAreRejected() throws {
        for mutation in [Fixture.Mutation.binary, .plist, .manifestPath] {
            let fixture = try Fixture(mutation: mutation)
            XCTAssertThrowsError(try fixture.verifier.verify(mode: .enabled))
        }
    }

    func testUnsafeMetadataAndHardLinksAreRejected() throws {
        let unsafeOwner = try Fixture(binaryMetadata: Fixture.metadata(ownerID: 501))
        XCTAssertThrowsError(try unsafeOwner.verifier.verify(mode: .enabled))
        let hardLinked = try Fixture(binaryMetadata: Fixture.metadata(linkCount: 2))
        XCTAssertThrowsError(try hardLinked.verifier.verify(mode: .enabled))
    }

    func testProhibitedEnvironmentVariablesAreRejected() throws {
        let fixture = try Fixture(plistEnvironment: true)
        XCTAssertThrowsError(try fixture.verifier.verify(mode: .enabled))
    }
}

private struct Fixture {
    enum Mutation { case none, binary, plist, manifestPath }
    static func metadata(
        ownerID: UInt32 = 0,
        permissions: UInt16 = 0o644,
        linkCount: UInt64 = 1
    ) -> ProductionFileMetadata {
        .init(ownerID: ownerID, groupID: 0, permissions: permissions, fileType: .regularFile,
              linkCount: linkCount, deviceID: 1, inode: 1)
    }

    let sourceCommit = String(repeating: "a", count: 40)
    let profileID = "m1-pro-0x8104-report-id-1-v1"
    let verifier: ProductionInstalledSetVerifier

    init(
        mode: String = "enabled",
        mutation: Mutation = .none,
        configMutation: ((inout [String: Any]) -> Void)? = nil,
        binaryMetadata: ProductionFileMetadata = Fixture.metadata(ownerID: 0, permissions: 0o755, linkCount: 1),
        plistEnvironment: Bool = false
    ) throws {
        let binary = Data("binary".utf8)
        var plist: [String: Any] = ["Label": "com.crazydennies.macbook-lid-monitor"]
        if plistEnvironment { plist["EnvironmentVariables"] = ["BAD": "1"] }
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let templateConfig: [String: Any] = [
            "SchemaVersion": 1, "Mode": mode,
            "HardwareProfileID": profileID, "SleepThreshold": 68,
            "ReopenThreshold": 72, "CloseDebounceSeconds": 2.0,
            "StartupCooldownSeconds": 15.0, "WakeRecoverySeconds": 15.0,
            "SensorFreshnessSeconds": 5.0,
        ]
        var config = templateConfig
        configMutation?(&config)
        let configData = try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0)
        let templateData = try PropertyListSerialization.data(
            fromPropertyList: templateConfig, format: .xml, options: 0
        )
        let normalizedConfig = try ProductionInstalledSetVerifier.normalizedConfigData(templateData)
        let hasher = ProductionSHA256Hasher()
        var manifest: [String: Any] = [
            "SchemaVersion": 1, "Product": "macbook-lid-monitor-daemon",
            "SourceCommit": sourceCommit, "Version": "version",
            "BinaryPath": ProductionInstalledSetPaths.binary,
            "BinarySHA256": hasher.hash(binary),
            "PlistPath": ProductionInstalledSetPaths.plist,
            "PlistSHA256": hasher.hash(plistData),
            "ConfigPath": ProductionInstalledSetPaths.config,
            "DisabledConfigSHA256": hasher.hash(normalizedConfig),
            "HardwareProfileID": profileID,
            "CrashBudgetPath": ProductionInstalledSetPaths.crashBudget,
            "SleepAuthorityPath": ProductionInstalledSetPaths.sleepAuthority,
            "AcceptanceStatePath": ProductionInstalledSetPaths.acceptance,
            "HealthStatePath": ProductionInstalledSetPaths.health,
        ]
        var effectiveBinary = binary
        var effectivePlist = plistData
        switch mutation {
        case .none: break
        case .binary: effectiveBinary.append(0)
        case .plist: effectivePlist.append(0)
        case .manifestPath: manifest["BinaryPath"] = "/wrong"
        }
        let manifestData = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        let reader = DictionaryProductionInstalledSetReader(values: [
            ProductionInstalledSetPaths.binary: (effectiveBinary, binaryMetadata),
            ProductionInstalledSetPaths.plist: (effectivePlist, Fixture.metadata()),
            ProductionInstalledSetPaths.config: (configData, Fixture.metadata()),
            ProductionInstalledSetPaths.manifest: (manifestData, Fixture.metadata()),
        ])
        verifier = ProductionInstalledSetVerifier(reader: reader, hasher: hasher)
    }
}

private final class DictionaryProductionInstalledSetReader: ProductionInstalledSetReading, @unchecked Sendable {
    let values: [String: (Data, ProductionFileMetadata)]
    init(values: [String: (Data, ProductionFileMetadata)]) { self.values = values }
    func read(path: String) throws -> (Data, ProductionFileMetadata) {
        guard let value = values[path] else { throw CocoaError(.fileNoSuchFile) }
        return value
    }
}
