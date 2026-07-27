import Foundation

struct ProductionInstallationMarkers: Equatable, Sendable {
    let binaryExists: Bool
    let plistExists: Bool
    let manifestExists: Bool
    let jobRegistered: Bool
    let managedLeaseExists: Bool

    var anyProductionMarker: Bool {
        binaryExists || plistExists || manifestExists || jobRegistered || managedLeaseExists
    }
}

enum SleepAuthorityPathResolution: Equatable, Sendable {
    case managed(String)
    case foregroundFallback(String)
    case unsafeInstalledState
}

struct SleepAuthorityPathResolver: Sendable {
    static let managedPath = "/Library/Application Support/MacBookLidMonitor/sleep-authority.lock"

    let binaryPath: String
    let plistPath: String
    let manifestPath: String
    let managedPath: String
    let fallbackPath: String

    init(
        binaryPath: String = "/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon",
        plistPath: String = "/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist",
        manifestPath: String = "/Library/Application Support/MacBookLidMonitor/manifest.plist",
        managedPath: String = Self.managedPath,
        fallbackPath: String = POSIXSleepAuthorityLease.fixedPath
    ) {
        self.binaryPath = binaryPath
        self.plistPath = plistPath
        self.manifestPath = manifestPath
        self.managedPath = managedPath
        self.fallbackPath = fallbackPath
    }

    func resolve(markers: ProductionInstallationMarkers) -> SleepAuthorityPathResolution {
        guard markers.anyProductionMarker else {
            return .foregroundFallback(fallbackPath)
        }
        guard markers.managedLeaseExists else {
            return .unsafeInstalledState
        }
        return .managed(managedPath)
    }

    func makeLease(markers: ProductionInstallationMarkers) throws -> SleepAuthorityLeasing {
        switch resolve(markers: markers) {
        case let .managed(path):
            return POSIXSleepAuthorityLease(path: path, policy: .managedProduction)
        case let .foregroundFallback(path):
            return POSIXSleepAuthorityLease(path: path, policy: .foregroundFallback)
        case .unsafeInstalledState:
            throw SleepAuthorityLeaseError.unsafePath
        }
    }

    func currentMarkers(
        fileManager: FileManager = .default,
        jobRegistered: Bool? = nil
    ) -> ProductionInstallationMarkers {
        ProductionInstallationMarkers(
            binaryExists: fileManager.fileExists(atPath: binaryPath),
            plistExists: fileManager.fileExists(atPath: plistPath),
            manifestExists: fileManager.fileExists(atPath: manifestPath),
            jobRegistered: jobRegistered ?? Self.systemJobRegistered(),
            managedLeaseExists: fileManager.fileExists(atPath: managedPath)
        )
    }

    private static func systemJobRegistered() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/com.crazydennies.macbook-lid-monitor"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
