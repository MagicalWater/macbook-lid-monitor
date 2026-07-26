import Foundation

enum ProductionMode: String, Equatable, Sendable {
    case disabled
    case dryRun = "dry-run"
    case enabled
}

struct ProductionConfiguration: Equatable, Sendable {
    let schemaVersion: Int
    let mode: ProductionMode
    let hardwareProfileID: String
    let policy: LidSleepPolicy
    let sensorFreshness: TimeInterval
}

enum ProductionConfigurationError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformedPropertyList
    case unsupportedKey(String)
    case missingField(String)
    case unsupportedSchemaVersion(Int)
    case unsupportedMode(String)
    case invalidHardwareProfileID
    case invalidSensorFreshness(TimeInterval)
    case invalidPolicy(String)
    case configurationIsSymbolicLink
    case configurationIsNotRegularFile
    case invalidConfigurationOwner(UInt32)
    case invalidConfigurationGroup(UInt32)
    case unsafeConfigurationPermissions(UInt16)

    var description: String {
        switch self {
        case .malformedPropertyList: return "malformed-property-list"
        case let .unsupportedKey(key): return "unsupported-key(\(key))"
        case let .missingField(field): return "missing-field(\(field))"
        case let .unsupportedSchemaVersion(version): return "unsupported-schema-version(\(version))"
        case let .unsupportedMode(mode): return "unsupported-mode(\(mode))"
        case .invalidHardwareProfileID: return "invalid-hardware-profile-id"
        case let .invalidSensorFreshness(value): return "invalid-sensor-freshness(\(value))"
        case let .invalidPolicy(reason): return "invalid-policy(\(reason))"
        case .configurationIsSymbolicLink: return "configuration-is-symbolic-link"
        case .configurationIsNotRegularFile: return "configuration-is-not-regular-file"
        case let .invalidConfigurationOwner(owner): return "invalid-configuration-owner(\(owner))"
        case let .invalidConfigurationGroup(group): return "invalid-configuration-group(\(group))"
        case let .unsafeConfigurationPermissions(mode): return "unsafe-configuration-permissions(\(String(mode, radix: 8)))"
        }
    }
}

struct ProductionConfigurationDecoder: Sendable {
    private static let allowedKeys: Set<String> = [
        "SchemaVersion", "Mode", "HardwareProfileID", "SleepThreshold",
        "ReopenThreshold", "CloseDebounceSeconds", "StartupCooldownSeconds",
        "WakeRecoverySeconds", "SensorFreshnessSeconds",
    ]

    func decode(_ data: Data) throws -> ProductionConfiguration {
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw ProductionConfigurationError.malformedPropertyList
        }
        guard let dictionary = object as? [String: Any] else {
            throw ProductionConfigurationError.malformedPropertyList
        }
        if let unsupported = Set(dictionary.keys).subtracting(Self.allowedKeys).sorted().first {
            throw ProductionConfigurationError.unsupportedKey(unsupported)
        }

        let schemaVersion: Int = try required("SchemaVersion", from: dictionary)
        guard schemaVersion == 1 else {
            throw ProductionConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        let rawMode: String = try required("Mode", from: dictionary)
        guard let mode = ProductionMode(rawValue: rawMode) else {
            throw ProductionConfigurationError.unsupportedMode(rawMode)
        }
        let hardwareProfileID: String = try required("HardwareProfileID", from: dictionary)
        guard !hardwareProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProductionConfigurationError.invalidHardwareProfileID
        }
        let sensorFreshness = try requiredNumber("SensorFreshnessSeconds", from: dictionary)
        guard sensorFreshness.isFinite, sensorFreshness > 0 else {
            throw ProductionConfigurationError.invalidSensorFreshness(sensorFreshness)
        }

        do {
            let policy = try LidSleepPolicy(
                sleepThreshold: try required("SleepThreshold", from: dictionary),
                reopenThreshold: try required("ReopenThreshold", from: dictionary),
                closeDebounce: try requiredNumber("CloseDebounceSeconds", from: dictionary),
                startupCooldown: try requiredNumber("StartupCooldownSeconds", from: dictionary),
                wakeRecovery: try requiredNumber("WakeRecoverySeconds", from: dictionary)
            )
            return ProductionConfiguration(
                schemaVersion: schemaVersion,
                mode: mode,
                hardwareProfileID: hardwareProfileID,
                policy: policy,
                sensorFreshness: sensorFreshness
            )
        } catch let error as ProductionConfigurationError {
            throw error
        } catch let error as LidSleepPolicyError {
            throw ProductionConfigurationError.invalidPolicy(stablePolicyError(error))
        }
    }

    private func required<T>(_ key: String, from dictionary: [String: Any]) throws -> T {
        guard let value = dictionary[key] else {
            throw ProductionConfigurationError.missingField(key)
        }
        guard let typed = value as? T else {
            throw ProductionConfigurationError.malformedPropertyList
        }
        return typed
    }

    private func requiredNumber(_ key: String, from dictionary: [String: Any]) throws -> TimeInterval {
        guard let value = dictionary[key] else {
            throw ProductionConfigurationError.missingField(key)
        }
        guard let number = value as? NSNumber else {
            throw ProductionConfigurationError.malformedPropertyList
        }
        return number.doubleValue
    }

    private func stablePolicyError(_ error: LidSleepPolicyError) -> String {
        switch error {
        case .invalidThresholdRelationship: return "invalid-threshold-relationship"
        case .invalidSleepThreshold: return "invalid-sleep-threshold"
        case .invalidReopenThreshold: return "invalid-reopen-threshold"
        case .invalidCloseDebounce: return "invalid-close-debounce"
        case .invalidStartupCooldown: return "invalid-startup-cooldown"
        case .invalidWakeRecovery: return "invalid-wake-recovery"
        }
    }
}
