import Foundation
import XCTest
@testable import LidMonitorCore

final class ProductionHealthStoreTests: XCTestCase {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    func testStoreWritesAtomic0600RedactedSnapshot() throws {
        let directory = root.appendingPathComponent(".build/production-health-atomic")
        try? FileManager.default.removeItem(at: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("health.json")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = ProductionHealthStore(path: path.path, now: { now }, pid: 42)

        try store.recordStarted(version: "abc", mode: .enabled, profileID: "profile")
        try store.recordState(.monitoringArmed, sampleTime: now)

        let data = try Data(contentsOf: path)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("serial"))
        XCTAssertFalse(text.contains("UUID"))
        XCTAssertFalse(text.contains("raw"))
        let directoryEntries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(directoryEntries.contains { $0.hasPrefix(".health.") })
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(ProductionHealthRecord.self, from: data)
        XCTAssertEqual(snapshot.pid, 42)
        XCTAssertEqual(snapshot.state, .monitoringArmed)
    }

    func testStoreWritesOnlyTransitionsErrorsAndBoundedHeartbeat() throws {
        let path = root.appendingPathComponent(".build/production-health-throttle/health.json")
        try? FileManager.default.removeItem(at: path.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let clock = LockedHealthBox(Date(timeIntervalSince1970: 100))
        let writes = LockedHealthBox(0)
        let store = ProductionHealthStore(
            path: path.path,
            heartbeatInterval: 60,
            now: { clock.value },
            pid: 7,
            didWrite: { writes.mutate { $0 += 1 } }
        )
        try store.recordStarted(version: "v", mode: .dryRun, profileID: "p")
        XCTAssertEqual(writes.value, 1)
        try store.recordState(.dryRun, sampleTime: clock.value)
        XCTAssertEqual(writes.value, 2)
        clock.mutate { $0 = $0.addingTimeInterval(10) }
        try store.recordState(.dryRun, sampleTime: clock.value)
        XCTAssertEqual(writes.value, 2)
        clock.mutate { $0 = $0.addingTimeInterval(60) }
        try store.recordState(.dryRun, sampleTime: clock.value)
        XCTAssertEqual(writes.value, 3)
        try store.recordError("sensor-unavailable")
        XCTAssertEqual(writes.value, 4)
        try store.recordError("sensor-unavailable")
        XCTAssertEqual(writes.value, 4)
        clock.mutate { $0 = $0.addingTimeInterval(10) }
        try store.recordSample(at: clock.value)
        XCTAssertEqual(writes.value, 4)
        clock.mutate { $0 = $0.addingTimeInterval(60) }
        try store.recordSample(at: clock.value)
        XCTAssertEqual(writes.value, 5)
    }

    func testReaderDistinguishesMissingCorruptStaleAndCurrent() throws {
        let path = root.appendingPathComponent(".build/production-health-read/health.json")
        try? FileManager.default.removeItem(at: path.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(ProductionHealthStore.read(path: path.path, now: now, staleAfter: 30), .missing)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: path)
        XCTAssertEqual(ProductionHealthStore.read(path: path.path, now: now, staleAfter: 30), .corrupt)
        let stale = ProductionHealthRecord(
            schemaVersion: 1, version: "v", mode: .enabled, profileID: "p", state: .monitoringDisarmed,
            pid: 1, lastTransitionTime: now.addingTimeInterval(-100), lastValidSampleTime: nil,
            lastErrorCode: nil, updatedAt: now.addingTimeInterval(-100)
        )
        try healthEncoder().encode(stale).write(to: path)
        XCTAssertEqual(ProductionHealthStore.read(path: path.path, now: now, staleAfter: 30), .stale(stale))
        let current = ProductionHealthRecord(
            schemaVersion: 1, version: "v", mode: .enabled, profileID: "p", state: .monitoringArmed,
            pid: 1, lastTransitionTime: now, lastValidSampleTime: now, lastErrorCode: nil, updatedAt: now
        )
        try healthEncoder().encode(current).write(to: path)
        XCTAssertEqual(ProductionHealthStore.read(path: path.path, now: now, staleAfter: 30), .current(current))
    }

    func testPersistingSinkForwardsEventsAndStoreFailureDoesNotThrow() {
        let downstream = RecordingHealthEventSink()
        let store = ProductionHealthStore(path: "/dev/null/health.json")
        let sink = ProductionHealthPersistingEventSink(
            downstream: downstream,
            store: store,
            version: "v"
        )
        sink.emit(.started(mode: .enabled, profileID: "p"))
        sink.emit(.healthChanged(.monitoringDisarmed))
        sink.emit(.degraded(code: "failure"))
        XCTAssertEqual(downstream.events.count, 3)
    }

    func testInstalledVersionReadsOnlyManifestVersion() throws {
        let directory = root.appendingPathComponent(".build/production-health-version")
        try? FileManager.default.removeItem(at: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appendingPathComponent("manifest.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["Version": "abc123", "SerialNumber": "must-not-be-read"],
            format: .xml,
            options: 0
        )
        try data.write(to: manifest)
        XCTAssertEqual(ProductionHealthStore.installedVersion(manifestPath: manifest.path), "abc123")
        XCTAssertEqual(
            ProductionHealthStore.installedVersion(manifestPath: directory.appendingPathComponent("missing").path),
            "unavailable"
        )
    }

    private func healthEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private final class RecordingHealthEventSink: ProductionEventSinking, @unchecked Sendable {
    var events: [ProductionEvent] = []
    func emit(_ event: ProductionEvent) { events.append(event) }
}

private final class LockedHealthBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}
