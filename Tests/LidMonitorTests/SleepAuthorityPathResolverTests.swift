import XCTest
@testable import LidMonitorCore

final class SleepAuthorityPathResolverTests: XCTestCase {
    func testInstalledProductionAndForegroundResolveSameManagedLease() {
        let resolver = SleepAuthorityPathResolver(
            managedPath: "/managed/lease",
            fallbackPath: "/tmp/fallback"
        )

        let result = resolver.resolve(markers: .init(
            binaryExists: true,
            plistExists: true,
            manifestExists: true,
            jobRegistered: true,
            managedLeaseExists: true
        ))

        XCTAssertEqual(result, .managed("/managed/lease"))
    }

    func testForegroundFallbackRequiresAllProductionMarkersAbsent() {
        let resolver = SleepAuthorityPathResolver(managedPath: "/managed", fallbackPath: "/fallback")
        XCTAssertEqual(
            resolver.resolve(markers: .init(
                binaryExists: false,
                plistExists: false,
                manifestExists: false,
                jobRegistered: false,
                managedLeaseExists: false
            )),
            .foregroundFallback("/fallback")
        )
    }

    func testLoadedProductionJobMarkerProhibitsFallback() {
        let resolver = SleepAuthorityPathResolver(managedPath: "/managed", fallbackPath: "/fallback")
        XCTAssertEqual(
            resolver.resolve(markers: .init(
                binaryExists: false,
                plistExists: false,
                manifestExists: false,
                jobRegistered: true,
                managedLeaseExists: false
            )),
            .unsafeInstalledState
        )
    }

    func testMissingManagedLeaseFailsOpenWhenProductionInstalled() {
        let resolver = SleepAuthorityPathResolver(managedPath: "/managed", fallbackPath: "/fallback")
        XCTAssertEqual(
            resolver.resolve(markers: .init(
                binaryExists: true,
                plistExists: false,
                manifestExists: false,
                jobRegistered: false,
                managedLeaseExists: false
            )),
            .unsafeInstalledState
        )
    }

    func testCurrentMarkersCanRepresentLoadedJobWithoutFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("authority-resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = SleepAuthorityPathResolver(
            binaryPath: root.appendingPathComponent("binary").path,
            plistPath: root.appendingPathComponent("plist").path,
            manifestPath: root.appendingPathComponent("manifest").path,
            managedPath: root.appendingPathComponent("lease").path,
            fallbackPath: root.appendingPathComponent("fallback").path
        )

        let markers = resolver.currentMarkers(jobRegistered: true)

        XCTAssertTrue(markers.jobRegistered)
        XCTAssertEqual(resolver.resolve(markers: markers), .unsafeInstalledState)
    }
}
