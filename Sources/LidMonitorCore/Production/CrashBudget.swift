import Foundation

protocol CrashBudgetStoring: AnyObject, Sendable {
    func load() throws -> Data?
    func storeAtomically(_ data: Data) throws
    func remove() throws
}

struct CrashBudgetSnapshot: Equatable, Sendable {
    let unexpectedExitCount: Int
    let isCircuitOpen: Bool
}

private struct CrashBudgetState: Codable, Equatable, Sendable {
    var unexpectedExitTimes: [TimeInterval]
    var circuitOpen: Bool
}

struct CrashBudget: Sendable {
    private let storage: CrashBudgetStoring
    private let maximumUnexpectedExits: Int
    private let window: TimeInterval

    init(
        storage: CrashBudgetStoring,
        maximumUnexpectedExits: Int,
        window: TimeInterval
    ) {
        self.storage = storage
        self.maximumUnexpectedExits = max(1, maximumUnexpectedExits)
        self.window = max(1, window)
    }

    mutating func allowsStart(at date: Date) throws -> Bool {
        do {
            guard let state = try loadState() else { return true }
            return !state.circuitOpen
        } catch is DecodingError {
            return false
        }
    }

    mutating func recordUnexpectedExit(at date: Date) throws -> CrashBudgetSnapshot {
        var state: CrashBudgetState
        do {
            state = try loadState() ?? CrashBudgetState(unexpectedExitTimes: [], circuitOpen: false)
        } catch is DecodingError {
            return CrashBudgetSnapshot(unexpectedExitCount: 0, isCircuitOpen: true)
        }
        let cutoff = date.timeIntervalSince1970 - window
        state.unexpectedExitTimes = state.unexpectedExitTimes.filter { $0 >= cutoff }
        state.unexpectedExitTimes.append(date.timeIntervalSince1970)
        if state.unexpectedExitTimes.count >= maximumUnexpectedExits {
            state.circuitOpen = true
        }
        try storage.storeAtomically(try JSONEncoder().encode(state))
        return CrashBudgetSnapshot(
            unexpectedExitCount: state.unexpectedExitTimes.count,
            isCircuitOpen: state.circuitOpen
        )
    }

    mutating func recordCleanExit() throws {
        _ = try storage.load()
    }

    mutating func reset() throws {
        try storage.remove()
    }

    private func loadState() throws -> CrashBudgetState? {
        guard let data = try storage.load() else { return nil }
        return try JSONDecoder().decode(CrashBudgetState.self, from: data)
    }
}

final class FileCrashBudgetStorage: CrashBudgetStoring, @unchecked Sendable {
    static let fixedPath = "/Library/Application Support/MacBookLidMonitor/crash-budget.json"

    private let path: String

    init(path: String = FileCrashBudgetStorage.fixedPath) {
        self.path = path
    }

    func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func storeAtomically(_ data: Data) throws {
        let url = URL(fileURLWithPath: path)
        try data.write(to: url, options: .atomic)
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }
}
