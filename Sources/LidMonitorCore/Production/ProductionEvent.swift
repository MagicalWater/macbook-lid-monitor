import Darwin
import Foundation

enum DaemonHealthState: String, Equatable, Sendable {
    case starting
    case disabled
    case monitoringDisarmed = "monitoring-disarmed"
    case monitoringArmed = "monitoring-armed"
    case dryRun = "dry-run"
    case incompatibleHardware = "incompatible-hardware"
    case degradedFailOpen = "degraded-fail-open"
    case stopping
}

enum ProductionEvent: Equatable, Sendable {
    case started(mode: ProductionMode, profileID: String)
    case healthChanged(DaemonHealthState)
    case stateChanged(DaemonHealthState, sensorValue: Int?)
    case degraded(code: String)
    case sleepRequested
    case stopping(reason: String)
}

struct ProductionEventFormatter: Sendable {
    let timestamp: @Sendable (Date) -> String
    let pid: Int32

    init(
        timestamp: @escaping @Sendable (Date) -> String = { ISO8601DateFormatter().string(from: $0) },
        pid: Int32 = getpid()
    ) {
        self.timestamp = timestamp
        self.pid = pid
    }

    func line(for event: ProductionEvent, at date: Date) -> String {
        let prefix = "timestamp=\(timestamp(date))"
        switch event {
        case let .started(mode, profileID):
            return "\(prefix) event=started pid=\(pid) mode=\(mode.rawValue) profile=\(profileID)"
        case let .healthChanged(state):
            return "\(prefix) event=health-changed pid=\(pid) state=\(state.rawValue)"
        case let .stateChanged(state, sensorValue):
            let sensor = sensorValue.map { " sensor=\($0)" } ?? ""
            return "\(prefix) event=state-changed pid=\(pid) state=\(state.rawValue)\(sensor)"
        case let .degraded(code):
            return "\(prefix) event=degraded pid=\(pid) code=\(code)"
        case .sleepRequested:
            return "\(prefix) event=sleep-requested pid=\(pid)"
        case let .stopping(reason):
            return "\(prefix) event=stopping pid=\(pid) reason=\(reason)"
        }
    }
}
