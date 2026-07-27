import Darwin
import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionFileSystemTests: XCTestCase {
    func testInspectorDistinguishesRegularDirectoryAndSymlinkWithoutFollowing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("production-filesystem-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let regular = root.appendingPathComponent("regular")
        let link = root.appendingPathComponent("link")
        XCTAssertTrue(FileManager.default.createFile(atPath: regular.path, contents: Data("x".utf8)))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: regular)

        let inspector = NativeProductionFileSystemInspector()
        let directoryMetadata = try inspector.metadata(at: root.path, followSymbolicLink: false)
        let regularMetadata = try inspector.metadata(at: regular.path, followSymbolicLink: false)
        let linkMetadata = try inspector.metadata(at: link.path, followSymbolicLink: false)

        XCTAssertEqual(directoryMetadata.fileType, .directory)
        XCTAssertEqual(regularMetadata.fileType, .regularFile)
        XCTAssertEqual(linkMetadata.fileType, .symbolicLink)
        XCTAssertEqual(regularMetadata.linkCount, 1)
        XCTAssertNotEqual(regularMetadata.inode, 0)
    }

    func testLegacyConfigurationMetadataInitializerMapsToSharedFileType() {
        let metadata = ProductionFileMetadata(
            ownerID: 0,
            groupID: 0,
            permissions: 0o644,
            isRegularFile: true,
            isSymbolicLink: false
        )

        XCTAssertEqual(metadata.fileType, .regularFile)
        XCTAssertTrue(metadata.isRegularFile)
        XCTAssertFalse(metadata.isSymbolicLink)
        XCTAssertEqual(metadata.linkCount, 1)
    }
}
