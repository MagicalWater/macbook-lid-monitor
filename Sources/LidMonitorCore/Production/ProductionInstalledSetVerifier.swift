import CryptoKit
import Foundation

enum ProductionInstalledSetPaths {
    static let binary = "/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon"
    static let plist = "/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist"
    static let config = "/Library/Application Support/MacBookLidMonitor/config.plist"
    static let manifest = "/Library/Application Support/MacBookLidMonitor/manifest.plist"
    static let crashBudget = "/Library/Application Support/MacBookLidMonitor/crash-budget.json"
    static let sleepAuthority = "/Library/Application Support/MacBookLidMonitor/sleep-authority.lock"
    static let acceptance = "/Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist"
    static let health = "/Library/Application Support/MacBookLidMonitor/health.plist"
}

struct ProductionInstalledSetIdentity: Equatable, Sendable {
    let sourceCommit: String
    let manifestSHA256: String
    let binarySHA256: String
    let plistSHA256: String
    let normalizedConfigSHA256: String
    let currentConfigSHA256: String
    let hardwareProfileID: String
}

protocol ProductionInstalledSetVerifying: Sendable {
    func verify(mode: ProductionMode) throws -> ProductionInstalledSetIdentity
}

protocol ProductionInstalledSetReading: Sendable {
    func read(path: String) throws -> (Data, ProductionFileMetadata)
}

protocol ProductionDataHashing: Sendable { func hash(_ data: Data) -> String }

struct ProductionSHA256Hasher: ProductionDataHashing {
    func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

final class NativeProductionInstalledSetReader: ProductionInstalledSetReading, @unchecked Sendable {
    private let inspector: ProductionFileSystemInspecting
    init(inspector: ProductionFileSystemInspecting = NativeProductionFileSystemInspector()) {
        self.inspector = inspector
    }
    func read(path: String) throws -> (Data, ProductionFileMetadata) {
        let metadata = try inspector.metadata(at: path, followSymbolicLink: false)
        return (try Data(contentsOf: URL(fileURLWithPath: path)), metadata)
    }
}

enum ProductionInstalledSetError: Error, Equatable { case invalid(String) }

struct ProductionInstalledSetVerifier: ProductionInstalledSetVerifying {
    let reader: ProductionInstalledSetReading
    let hasher: ProductionDataHashing

    init(
        reader: ProductionInstalledSetReading = NativeProductionInstalledSetReader(),
        hasher: ProductionDataHashing = ProductionSHA256Hasher()
    ) {
        self.reader = reader
        self.hasher = hasher
    }

    func verify(mode: ProductionMode) throws -> ProductionInstalledSetIdentity {
        let (binary, binaryMeta) = try reader.read(path: ProductionInstalledSetPaths.binary)
        let (plist, plistMeta) = try reader.read(path: ProductionInstalledSetPaths.plist)
        let (config, configMeta) = try reader.read(path: ProductionInstalledSetPaths.config)
        let (manifest, manifestMeta) = try reader.read(path: ProductionInstalledSetPaths.manifest)
        try validate(metadata: binaryMeta, mode: 0o755, name: "binary")
        for (metadata, name) in [(plistMeta, "plist"), (configMeta, "config"), (manifestMeta, "manifest")] {
            try validate(metadata: metadata, mode: 0o644, name: name)
        }
        guard let manifestObject = try PropertyListSerialization.propertyList(from: manifest, format: nil) as? [String: Any] else {
            throw ProductionInstalledSetError.invalid("manifest")
        }
        func string(_ key: String) throws -> String {
            guard let value = manifestObject[key] as? String else { throw ProductionInstalledSetError.invalid(key) }
            return value
        }
        guard manifestObject["SchemaVersion"] as? Int == 1,
              try string("BinaryPath") == ProductionInstalledSetPaths.binary,
              try string("PlistPath") == ProductionInstalledSetPaths.plist,
              try string("ConfigPath") == ProductionInstalledSetPaths.config,
              try string("CrashBudgetPath") == ProductionInstalledSetPaths.crashBudget,
              try string("SleepAuthorityPath") == ProductionInstalledSetPaths.sleepAuthority,
              try string("AcceptanceStatePath") == ProductionInstalledSetPaths.acceptance,
              try string("HealthStatePath") == ProductionInstalledSetPaths.health else {
            throw ProductionInstalledSetError.invalid("paths")
        }
        if let plistObject = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
           plistObject["EnvironmentVariables"] != nil {
            throw ProductionInstalledSetError.invalid("environment")
        }
        let binaryHash = hasher.hash(binary), plistHash = hasher.hash(plist)
        let normalizedHash = hasher.hash(try Self.normalizedConfigData(config))
        guard binaryHash == (try string("BinarySHA256")),
              plistHash == (try string("PlistSHA256")),
              normalizedHash == (try string("DisabledConfigSHA256")) else {
            throw ProductionInstalledSetError.invalid("checksum")
        }
        let decoded = try ProductionConfigurationDecoder().decode(config)
        guard decoded.mode == mode, decoded.hardwareProfileID == (try string("HardwareProfileID")) else {
            throw ProductionInstalledSetError.invalid("config")
        }
        return .init(sourceCommit: try string("SourceCommit"), manifestSHA256: hasher.hash(manifest),
                     binarySHA256: binaryHash, plistSHA256: plistHash,
                     normalizedConfigSHA256: normalizedHash, currentConfigSHA256: hasher.hash(config),
                     hardwareProfileID: decoded.hardwareProfileID)
    }

    static func normalizedConfigData(_ data: Data) throws -> Data {
        guard var object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ProductionInstalledSetError.invalid("config")
        }
        object["Mode"] = "disabled"
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ProductionInstalledSetError.invalid("config")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func validate(metadata: ProductionFileMetadata, mode: UInt16, name: String) throws {
        guard metadata.fileType == .regularFile, metadata.ownerID == 0, metadata.groupID == 0,
              metadata.permissions == mode, metadata.linkCount == 1 else {
            throw ProductionInstalledSetError.invalid(name)
        }
    }
}
