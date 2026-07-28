import Darwin
import Foundation

enum SleepAuthorityLeaseError: Error, Equatable, Sendable {
    case alreadyHeld
    case unsafePath
    case unsafeParent
    case unsafeMetadata
    case pathReplaced
    case ioFailure(Int32)
}

struct SleepAuthorityLeasePolicy: Equatable, Sendable {
    let createIfMissing: Bool
    let expectedFileOwnerID: UInt32?
    let expectedFileGroupID: UInt32?
    let expectedFilePermissions: UInt16?
    let expectedParentOwnerID: UInt32?
    let expectedParentGroupID: UInt32?
    let rejectsParentGroupOrWorldWrite: Bool
    let requiresSingleLink: Bool

    static let foregroundFallback = SleepAuthorityLeasePolicy(
        createIfMissing: true,
        expectedFileOwnerID: nil,
        expectedFileGroupID: nil,
        expectedFilePermissions: 0o666,
        expectedParentOwnerID: nil,
        expectedParentGroupID: nil,
        rejectsParentGroupOrWorldWrite: false,
        requiresSingleLink: true
    )

    static let managedProduction = SleepAuthorityLeasePolicy(
        createIfMissing: false,
        expectedFileOwnerID: 0,
        expectedFileGroupID: 0,
        expectedFilePermissions: 0o600,
        expectedParentOwnerID: 0,
        expectedParentGroupID: 0,
        rejectsParentGroupOrWorldWrite: true,
        requiresSingleLink: true
    )
}

protocol SleepAuthorityHolding: AnyObject, Sendable {}

protocol SleepAuthorityLeasing: Sendable {
    func acquire() throws -> SleepAuthorityHolding
}

final class POSIXSleepAuthorityLease: SleepAuthorityLeasing, @unchecked Sendable {
    static let fixedPath = "/tmp/com.crazydennies.macbook-lid-monitor.sleep-authority.lock"

    private let path: String
    private let policy: SleepAuthorityLeasePolicy
    private let inspector: ProductionFileSystemInspecting

    init(
        path: String = POSIXSleepAuthorityLease.fixedPath,
        policy: SleepAuthorityLeasePolicy = .foregroundFallback,
        inspector: ProductionFileSystemInspecting = NativeProductionFileSystemInspector()
    ) {
        self.path = path
        self.policy = policy
        self.inspector = inspector
    }

    func acquire() throws -> SleepAuthorityHolding {
        try validateParentIfRequired()

        let beforeOpen = try metadataBeforeOpen()
        if beforeOpen?.isSymbolicLink == true {
            throw SleepAuthorityLeaseError.unsafePath
        }
        if let beforeOpen {
            try validateFileMetadata(beforeOpen)
        }

        var flags = O_RDWR | O_NOFOLLOW
        if policy.createIfMissing {
            flags |= O_CREAT
        }
        let descriptor = open(path, flags, mode_t(0o666))
        guard descriptor >= 0 else {
            if errno == ELOOP { throw SleepAuthorityLeaseError.unsafePath }
            throw SleepAuthorityLeaseError.ioFailure(errno)
        }
        do {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else {
                throw SleepAuthorityLeaseError.ioFailure(errno)
            }
            if policy.createIfMissing, let expectedPermissions = policy.expectedFilePermissions {
                guard fchmod(descriptor, mode_t(expectedPermissions)) == 0 else {
                    throw SleepAuthorityLeaseError.ioFailure(errno)
                }
                guard fstat(descriptor, &info) == 0 else {
                    throw SleepAuthorityLeaseError.ioFailure(errno)
                }
            }
            let openedMetadata = ProductionFileMetadata(stat: info)
            if let beforeOpen,
               beforeOpen.deviceID != openedMetadata.deviceID || beforeOpen.inode != openedMetadata.inode {
                throw SleepAuthorityLeaseError.pathReplaced
            }
            try validateFileMetadata(openedMetadata)
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    throw SleepAuthorityLeaseError.alreadyHeld
                }
                throw SleepAuthorityLeaseError.ioFailure(errno)
            }
            return POSIXSleepAuthorityHolding(descriptor: descriptor)
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func validateParentIfRequired() throws {
        let requiresValidation = policy.expectedParentOwnerID != nil
            || policy.expectedParentGroupID != nil
            || policy.rejectsParentGroupOrWorldWrite
        guard requiresValidation else { return }

        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let metadata: ProductionFileMetadata
        do {
            metadata = try inspector.metadata(at: parent, followSymbolicLink: false)
        } catch let error as POSIXError {
            throw SleepAuthorityLeaseError.ioFailure(error.code.rawValue)
        }
        guard metadata.fileType == .directory else {
            throw SleepAuthorityLeaseError.unsafeParent
        }
        if let expected = policy.expectedParentOwnerID, metadata.ownerID != expected {
            throw SleepAuthorityLeaseError.unsafeParent
        }
        if let expected = policy.expectedParentGroupID, metadata.groupID != expected {
            throw SleepAuthorityLeaseError.unsafeParent
        }
        if policy.rejectsParentGroupOrWorldWrite, metadata.permissions & 0o022 != 0 {
            throw SleepAuthorityLeaseError.unsafeParent
        }
    }

    private func metadataBeforeOpen() throws -> ProductionFileMetadata? {
        do {
            return try inspector.metadata(at: path, followSymbolicLink: false)
        } catch let error as POSIXError where error.code == .ENOENT && policy.createIfMissing {
            return nil
        } catch let error as POSIXError {
            throw SleepAuthorityLeaseError.ioFailure(error.code.rawValue)
        }
    }

    private func validateFileMetadata(_ metadata: ProductionFileMetadata) throws {
        guard metadata.fileType == .regularFile else {
            throw metadata.fileType == .symbolicLink
                ? SleepAuthorityLeaseError.unsafePath
                : SleepAuthorityLeaseError.unsafeMetadata
        }
        if let expected = policy.expectedFileOwnerID, metadata.ownerID != expected {
            throw SleepAuthorityLeaseError.unsafeMetadata
        }
        if let expected = policy.expectedFileGroupID, metadata.groupID != expected {
            throw SleepAuthorityLeaseError.unsafeMetadata
        }
        if let expected = policy.expectedFilePermissions, metadata.permissions != expected {
            throw SleepAuthorityLeaseError.unsafeMetadata
        }
        if policy.requiresSingleLink, metadata.linkCount != 1 {
            throw SleepAuthorityLeaseError.unsafeMetadata
        }
    }
}

private final class POSIXSleepAuthorityHolding: SleepAuthorityHolding, @unchecked Sendable {
    private let descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
