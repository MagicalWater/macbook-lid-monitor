import Darwin
import Foundation

struct ProductionFileMetadata: Equatable, Sendable {
    let ownerID: UInt32
    let groupID: UInt32
    let permissions: UInt16
    let isRegularFile: Bool
    let isSymbolicLink: Bool
}

protocol ProductionConfigurationReading: AnyObject, Sendable {
    func read(path: String) throws -> (Data, ProductionFileMetadata)
}

final class NativeProductionConfigurationReader: ProductionConfigurationReading, @unchecked Sendable {
    func read(path: String) throws -> (Data, ProductionFileMetadata) {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let type = info.st_mode & S_IFMT
        let metadata = ProductionFileMetadata(
            ownerID: info.st_uid,
            groupID: info.st_gid,
            permissions: UInt16(info.st_mode & 0o7777),
            isRegularFile: type == S_IFREG,
            isSymbolicLink: type == S_IFLNK
        )
        return (try Data(contentsOf: URL(fileURLWithPath: path)), metadata)
    }
}

struct ProductionConfigurationLoader: Sendable {
    static let fixedPath = "/Library/Application Support/MacBookLidMonitor/config.plist"

    private let reader: ProductionConfigurationReading
    private let decoder: ProductionConfigurationDecoder

    init(
        reader: ProductionConfigurationReading = NativeProductionConfigurationReader(),
        decoder: ProductionConfigurationDecoder = ProductionConfigurationDecoder()
    ) {
        self.reader = reader
        self.decoder = decoder
    }

    func load() throws -> ProductionConfiguration {
        let (data, metadata) = try reader.read(path: Self.fixedPath)
        if metadata.isSymbolicLink {
            throw ProductionConfigurationError.configurationIsSymbolicLink
        }
        guard metadata.isRegularFile else {
            throw ProductionConfigurationError.configurationIsNotRegularFile
        }
        guard metadata.ownerID == 0 else {
            throw ProductionConfigurationError.invalidConfigurationOwner(metadata.ownerID)
        }
        guard metadata.groupID == 0 else {
            throw ProductionConfigurationError.invalidConfigurationGroup(metadata.groupID)
        }
        guard metadata.permissions & 0o022 == 0 else {
            throw ProductionConfigurationError.unsafeConfigurationPermissions(metadata.permissions)
        }
        return try decoder.decode(data)
    }
}
