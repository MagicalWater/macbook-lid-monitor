import Darwin
import Foundation
import XCTest
@testable import LidMonitorCore

final class SleepAuthorityLeaseTests: XCTestCase {
    func testManagedProductionPolicyMatchesInstalledLeasePermissions() {
        XCTAssertEqual(SleepAuthorityLeasePolicy.managedProduction.expectedFilePermissions, 0o600)
    }

    func testSecondLeaseIsRejectedUntilFirstIsReleased() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbook-lid-monitor-authority-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let lease = POSIXSleepAuthorityLease(path: path)

        var first: SleepAuthorityHolding? = try lease.acquire()
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try lease.acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .alreadyHeld)
        }
        first = nil
        XCTAssertNoThrow(try lease.acquire())
    }

    func testSymlinkPathIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbook-lid-monitor-authority-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        let link = directory.appendingPathComponent("lease")
        FileManager.default.createFile(atPath: target.path, contents: Data())
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try POSIXSleepAuthorityLease(path: link.path).acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafePath)
        }
    }

    func testManagedLeaseAcceptsOneExistingSafeRegularInode() throws {
        let directory = try makeDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)

        let policy = managedPolicy(
            ownerID: UInt32(getuid()),
            groupID: UInt32(getgid())
        )
        let lease = POSIXSleepAuthorityLease(path: leaseURL.path, policy: policy)

        XCTAssertNoThrow(try lease.acquire())
    }

    func testManagedLeaseRejectsGroupWritableParent() throws {
        let directory = try makeDirectory(mode: 0o775)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)

        XCTAssertThrowsError(
            try POSIXSleepAuthorityLease(
                path: leaseURL.path,
                policy: managedPolicy(ownerID: UInt32(getuid()), groupID: UInt32(getgid()))
            ).acquire()
        ) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafeParent)
        }
    }

    func testManagedLeaseRejectsUnexpectedParentOwner() throws {
        let directory = try makeDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)

        let policy = SleepAuthorityLeasePolicy(
            createIfMissing: false,
            expectedFileOwnerID: UInt32(getuid()),
            expectedFileGroupID: UInt32(getgid()),
            expectedFilePermissions: 0o666,
            expectedParentOwnerID: UInt32(getuid()) &+ 1,
            expectedParentGroupID: UInt32(getgid()),
            rejectsParentGroupOrWorldWrite: true,
            requiresSingleLink: true
        )

        XCTAssertThrowsError(try POSIXSleepAuthorityLease(path: leaseURL.path, policy: policy).acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafeParent)
        }
    }

    func testManagedLeaseRejectsUnexpectedParentGroup() throws {
        let directory = try makeDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)

        let policy = SleepAuthorityLeasePolicy(
            createIfMissing: false,
            expectedFileOwnerID: UInt32(getuid()),
            expectedFileGroupID: UInt32(getgid()),
            expectedFilePermissions: 0o666,
            expectedParentOwnerID: UInt32(getuid()),
            expectedParentGroupID: UInt32(getgid()) &+ 1,
            rejectsParentGroupOrWorldWrite: true,
            requiresSingleLink: true
        )

        XCTAssertThrowsError(try POSIXSleepAuthorityLease(path: leaseURL.path, policy: policy).acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafeParent)
        }
    }

    func testManagedLeaseRejectsUnexpectedModeAndHardLinkCount() throws {
        let directory = try makeDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")
        let secondLink = directory.appendingPathComponent("lease-hard-link")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o600), 0)

        let policy = managedPolicy(ownerID: UInt32(getuid()), groupID: UInt32(getgid()))
        XCTAssertThrowsError(try POSIXSleepAuthorityLease(path: leaseURL.path, policy: policy).acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafeMetadata)
        }

        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)
        try FileManager.default.linkItem(at: leaseURL, to: secondLink)
        XCTAssertThrowsError(try POSIXSleepAuthorityLease(path: leaseURL.path, policy: policy).acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafeMetadata)
        }
    }

    func testManagedLeaseRejectsUnexpectedFileOwner() throws {
        let directory = try makeDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)

        let policy = SleepAuthorityLeasePolicy(
            createIfMissing: false,
            expectedFileOwnerID: UInt32(getuid()) &+ 1,
            expectedFileGroupID: UInt32(getgid()),
            expectedFilePermissions: 0o666,
            expectedParentOwnerID: UInt32(getuid()),
            expectedParentGroupID: UInt32(getgid()),
            rejectsParentGroupOrWorldWrite: true,
            requiresSingleLink: true
        )

        XCTAssertThrowsError(try POSIXSleepAuthorityLease(path: leaseURL.path, policy: policy).acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafeMetadata)
        }
    }

    func testManagedLeaseRejectsUnexpectedFileGroup() throws {
        let directory = try makeDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)

        let policy = SleepAuthorityLeasePolicy(
            createIfMissing: false,
            expectedFileOwnerID: UInt32(getuid()),
            expectedFileGroupID: UInt32(getgid()) &+ 1,
            expectedFilePermissions: 0o666,
            expectedParentOwnerID: UInt32(getuid()),
            expectedParentGroupID: UInt32(getgid()),
            rejectsParentGroupOrWorldWrite: true,
            requiresSingleLink: true
        )

        XCTAssertThrowsError(try POSIXSleepAuthorityLease(path: leaseURL.path, policy: policy).acquire()) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafeMetadata)
        }
    }

    func testManagedPolicyRejectsReplacementSplitInUnsafeParent() throws {
        let directory = try makeDirectory(mode: 0o777)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")

        var first: SleepAuthorityHolding? = try POSIXSleepAuthorityLease(path: leaseURL.path).acquire()
        XCTAssertNotNil(first)
        try FileManager.default.removeItem(at: leaseURL)
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)

        XCTAssertThrowsError(
            try POSIXSleepAuthorityLease(
                path: leaseURL.path,
                policy: managedPolicy(ownerID: UInt32(getuid()), groupID: UInt32(getgid()))
            ).acquire()
        ) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .unsafeParent)
        }
        first = nil
    }

    func testLeaseRejectsWhenPreopenAndOpenedInodesDiffer() throws {
        let directory = try makeDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appendingPathComponent("lease")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data()))
        XCTAssertEqual(chmod(leaseURL.path, 0o666), 0)

        let actual = try NativeProductionFileSystemInspector()
            .metadata(at: leaseURL.path, followSymbolicLink: false)
        let replaced = ProductionFileMetadata(
            ownerID: actual.ownerID,
            groupID: actual.groupID,
            permissions: actual.permissions,
            fileType: actual.fileType,
            linkCount: actual.linkCount,
            deviceID: actual.deviceID,
            inode: actual.inode &+ 1
        )
        let policy = SleepAuthorityLeasePolicy(
            createIfMissing: false,
            expectedFileOwnerID: actual.ownerID,
            expectedFileGroupID: actual.groupID,
            expectedFilePermissions: actual.permissions,
            expectedParentOwnerID: nil,
            expectedParentGroupID: nil,
            rejectsParentGroupOrWorldWrite: false,
            requiresSingleLink: true
        )

        XCTAssertThrowsError(
            try POSIXSleepAuthorityLease(
                path: leaseURL.path,
                policy: policy,
                inspector: StaticProductionFileSystemInspector(metadata: replaced)
            ).acquire()
        ) { error in
            XCTAssertEqual(error as? SleepAuthorityLeaseError, .pathReplaced)
        }
    }

    private func makeDirectory(mode: mode_t) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbook-lid-monitor-authority-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertEqual(chmod(directory.path, mode), 0)
        return directory
    }

    private func managedPolicy(ownerID: UInt32, groupID: UInt32) -> SleepAuthorityLeasePolicy {
        SleepAuthorityLeasePolicy(
            createIfMissing: false,
            expectedFileOwnerID: ownerID,
            expectedFileGroupID: groupID,
            expectedFilePermissions: 0o666,
            expectedParentOwnerID: ownerID,
            expectedParentGroupID: groupID,
            rejectsParentGroupOrWorldWrite: true,
            requiresSingleLink: true
        )
    }
}

private struct StaticProductionFileSystemInspector: ProductionFileSystemInspecting {
    let metadata: ProductionFileMetadata

    func metadata(at path: String, followSymbolicLink: Bool) throws -> ProductionFileMetadata {
        metadata
    }
}
