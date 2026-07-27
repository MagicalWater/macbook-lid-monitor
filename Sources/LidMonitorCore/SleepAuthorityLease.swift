import Darwin
import Foundation

enum SleepAuthorityLeaseError: Error, Equatable, Sendable {
    case alreadyHeld
    case unsafePath
    case ioFailure(Int32)
}

protocol SleepAuthorityHolding: AnyObject, Sendable {}

protocol SleepAuthorityLeasing: Sendable {
    func acquire() throws -> SleepAuthorityHolding
}

final class POSIXSleepAuthorityLease: SleepAuthorityLeasing, @unchecked Sendable {
    static let fixedPath = "/tmp/com.crazydennies.macbook-lid-monitor.sleep-authority.lock"

    private let path: String

    init(path: String = POSIXSleepAuthorityLease.fixedPath) {
        self.path = path
    }

    func acquire() throws -> SleepAuthorityHolding {
        let descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o666))
        guard descriptor >= 0 else {
            if errno == ELOOP { throw SleepAuthorityLeaseError.unsafePath }
            throw SleepAuthorityLeaseError.ioFailure(errno)
        }
        do {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else {
                throw SleepAuthorityLeaseError.ioFailure(errno)
            }
            guard info.st_mode & S_IFMT == S_IFREG else {
                throw SleepAuthorityLeaseError.unsafePath
            }
            guard fchmod(descriptor, mode_t(0o666)) == 0 else {
                throw SleepAuthorityLeaseError.ioFailure(errno)
            }
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
