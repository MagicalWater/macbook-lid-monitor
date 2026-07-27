import Foundation

struct DaemonHealthSnapshot: Equatable, Sendable {
    let version: String
    let mode: ProductionMode
    let profileID: String
    let state: DaemonHealthState
    let lastTransitionTime: Date?
    let lastValidSampleTime: Date?
    let lastValidSampleAge: TimeInterval?
    let lastErrorCode: String?
}

struct DaemonHealth: Sendable {
    let version: String
    let mode: ProductionMode
    let profileID: String
    private(set) var state: DaemonHealthState = .starting
    private var lastTransitionTime: Date?
    private var lastValidSampleTime: Date?
    private var lastErrorCode: String?

    init(version: String, mode: ProductionMode, profileID: String) {
        self.version = version
        self.mode = mode
        self.profileID = profileID
    }

    mutating func transition(to state: DaemonHealthState, at date: Date) {
        self.state = state
        lastTransitionTime = date
    }

    mutating func recordSample(at date: Date) {
        lastValidSampleTime = date
    }

    mutating func recordError(_ code: String) {
        lastErrorCode = code
    }

    func snapshot(now: Date) -> DaemonHealthSnapshot {
        DaemonHealthSnapshot(
            version: version,
            mode: mode,
            profileID: profileID,
            state: state,
            lastTransitionTime: lastTransitionTime,
            lastValidSampleTime: lastValidSampleTime,
            lastValidSampleAge: lastValidSampleTime.map { max(0, now.timeIntervalSince($0)) },
            lastErrorCode: lastErrorCode
        )
    }
}
