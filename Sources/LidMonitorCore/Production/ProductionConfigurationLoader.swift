import Foundation

protocol ProductionConfigurationReading: AnyObject, Sendable {
    func read(path: String) throws -> (Data, ProductionFileMetadata)
}

final class NativeProductionConfigurationReader: ProductionConfigurationReading, @unchecked Sendable {
    private let inspector: ProductionFileSystemInspecting

    init(inspector: ProductionFileSystemInspecting = NativeProductionFileSystemInspector()) {
        self.inspector = inspector
    }

    func read(path: String) throws -> (Data, ProductionFileMetadata) {
        let metadata = try inspector.metadata(at: path, followSymbolicLink: false)
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
