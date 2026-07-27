import Darwin
import Foundation

enum ProductionFileType: Equatable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

struct ProductionFileMetadata: Equatable, Sendable {
    let ownerID: UInt32
    let groupID: UInt32
    let permissions: UInt16
    let fileType: ProductionFileType
    let linkCount: UInt64
    let deviceID: UInt64
    let inode: UInt64

    var isRegularFile: Bool { fileType == .regularFile }
    var isSymbolicLink: Bool { fileType == .symbolicLink }

    init(
        ownerID: UInt32,
        groupID: UInt32,
        permissions: UInt16,
        fileType: ProductionFileType,
        linkCount: UInt64,
        deviceID: UInt64,
        inode: UInt64
    ) {
        self.ownerID = ownerID
        self.groupID = groupID
        self.permissions = permissions
        self.fileType = fileType
        self.linkCount = linkCount
        self.deviceID = deviceID
        self.inode = inode
    }

    init(
        ownerID: UInt32,
        groupID: UInt32,
        permissions: UInt16,
        isRegularFile: Bool,
        isSymbolicLink: Bool
    ) {
        let fileType: ProductionFileType
        if isSymbolicLink {
            fileType = .symbolicLink
        } else if isRegularFile {
            fileType = .regularFile
        } else {
            fileType = .other
        }
        self.init(
            ownerID: ownerID,
            groupID: groupID,
            permissions: permissions,
            fileType: fileType,
            linkCount: 1,
            deviceID: 0,
            inode: 0
        )
    }

    init(stat info: stat) {
        let type = info.st_mode & S_IFMT
        let fileType: ProductionFileType
        switch type {
        case S_IFREG: fileType = .regularFile
        case S_IFDIR: fileType = .directory
        case S_IFLNK: fileType = .symbolicLink
        default: fileType = .other
        }
        self.init(
            ownerID: info.st_uid,
            groupID: info.st_gid,
            permissions: UInt16(info.st_mode & 0o7777),
            fileType: fileType,
            linkCount: UInt64(info.st_nlink),
            deviceID: UInt64(info.st_dev),
            inode: UInt64(info.st_ino)
        )
    }
}

protocol ProductionFileSystemInspecting: Sendable {
    func metadata(at path: String, followSymbolicLink: Bool) throws -> ProductionFileMetadata
}

struct NativeProductionFileSystemInspector: ProductionFileSystemInspecting, Sendable {
    func metadata(at path: String, followSymbolicLink: Bool) throws -> ProductionFileMetadata {
        var info = stat()
        let flags = followSymbolicLink ? 0 : AT_SYMLINK_NOFOLLOW
        let result = path.withCString { pointer in
            fstatat(AT_FDCWD, pointer, &info, flags)
        }
        guard result == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        return ProductionFileMetadata(stat: info)
    }
}
