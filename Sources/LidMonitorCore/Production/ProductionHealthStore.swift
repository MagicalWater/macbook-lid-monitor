import Darwin
import Foundation

struct ProductionHealthRecord: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let version: String
    let mode: ProductionMode
    let profileID: String
    let state: DaemonHealthState
    let pid: Int32
    let lastTransitionTime: Date?
    let lastValidSampleTime: Date?
    let lastErrorCode: String?
    let updatedAt: Date
}

enum ProductionHealthReadResult: Equatable, Sendable {
    case missing
    case corrupt
    case stale(ProductionHealthRecord)
    case current(ProductionHealthRecord)
}

final class ProductionHealthStore: @unchecked Sendable {
    private let path: String
    private let heartbeatInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let pid: Int32
    private let didWrite: @Sendable () -> Void
    private let lock = NSLock()
    private var health: DaemonHealth?
    private var lastWriteTime: Date?

    init(
        path: String = "/Library/Application Support/MacBookLidMonitor/health.plist",
        heartbeatInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init,
        pid: Int32 = getpid(),
        didWrite: @escaping @Sendable () -> Void = {}
    ) {
        self.path = path
        self.heartbeatInterval = heartbeatInterval
        self.now = now
        self.pid = pid
        self.didWrite = didWrite
    }

    func recordStarted(version: String, mode: ProductionMode, profileID: String) throws {
        try lock.withLock {
            let timestamp = now()
            var initial = DaemonHealth(version: version, mode: mode, profileID: profileID)
            initial.transition(to: .starting, at: timestamp)
            health = initial
            try persistLocked(at: timestamp)
        }
    }

    func recordState(_ state: DaemonHealthState, sampleTime: Date? = nil) throws {
        try lock.withLock {
            guard var current = health else { return }
            let timestamp = now()
            let isTransition = current.state != state
            let heartbeatDue = sampleTime != nil && lastWriteTime.map {
                timestamp.timeIntervalSince($0) >= heartbeatInterval
            } ?? true
            if isTransition { current.transition(to: state, at: timestamp) }
            if let sampleTime { current.recordSample(at: sampleTime) }
            health = current
            guard isTransition || heartbeatDue else { return }
            try persistLocked(at: timestamp)
        }
    }

    func recordError(_ code: String) throws {
        try lock.withLock {
            guard var current = health else { return }
            let timestamp = now()
            guard current.snapshot(now: timestamp).lastErrorCode != code else { return }
            current.recordError(code)
            health = current
            try persistLocked(at: timestamp)
        }
    }

    func recordSample(at date: Date) throws {
        try lock.withLock {
            guard var current = health else { return }
            let timestamp = now()
            let heartbeatDue = lastWriteTime.map {
                timestamp.timeIntervalSince($0) >= heartbeatInterval
            } ?? true
            current.recordSample(at: date)
            health = current
            guard heartbeatDue else { return }
            try persistLocked(at: timestamp)
        }
    }

    static func read(path: String, now: Date = Date(), staleAfter: TimeInterval = 180) -> ProductionHealthReadResult {
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(ProductionHealthRecord.self, from: data)
            guard record.schemaVersion == 1 else { return .corrupt }
            return now.timeIntervalSince(record.updatedAt) > staleAfter ? .stale(record) : .current(record)
        } catch {
            return .corrupt
        }
    }

    static func installedVersion(
        manifestPath: String = "/Library/Application Support/MacBookLidMonitor/manifest.plist"
    ) -> String {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = plist as? [String: Any],
            let version = dictionary["Version"] as? String,
            !version.isEmpty
        else { return "unavailable" }
        return version
    }

    private func persistLocked(at timestamp: Date) throws {
        guard let health else { return }
        let snapshot = health.snapshot(now: timestamp)
        let record = ProductionHealthRecord(
            schemaVersion: 1,
            version: snapshot.version,
            mode: snapshot.mode,
            profileID: snapshot.profileID,
            state: snapshot.state,
            pid: pid,
            lastTransitionTime: snapshot.lastTransitionTime,
            lastValidSampleTime: snapshot.lastValidSampleTime,
            lastErrorCode: snapshot.lastErrorCode,
            updatedAt: timestamp
        )
        let destination = URL(fileURLWithPath: path)
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".health.\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let renameResult = temporary.path.withCString { source in
            destination.path.withCString { target in Darwin.rename(source, target) }
        }
        guard renameResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        lastWriteTime = timestamp
        didWrite()
    }
}

final class ProductionHealthPersistingEventSink: ProductionEventSinking, @unchecked Sendable {
    private let downstream: ProductionEventSinking
    private let store: ProductionHealthStore
    private let version: String
    private let now: @Sendable () -> Date

    init(
        downstream: ProductionEventSinking,
        store: ProductionHealthStore,
        version: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.downstream = downstream
        self.store = store
        self.version = version
        self.now = now
    }

    func emit(_ event: ProductionEvent) {
        downstream.emit(event)
        do {
            switch event {
            case let .started(mode, profileID):
                try store.recordStarted(version: version, mode: mode, profileID: profileID)
            case let .healthChanged(state):
                try store.recordState(state)
            case let .stateChanged(state, _):
                try store.recordState(state, sampleTime: now())
            case let .degraded(code):
                try store.recordError(code)
            case .stopping:
                try store.recordState(.stopping)
            case .transition, .sleepRequested:
                break
            }
        } catch {
            // Health persistence must never create or block sleep authority.
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
