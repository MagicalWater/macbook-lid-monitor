import Darwin
import Foundation

struct RuntimeIdentity: Equatable, Sendable {
    let pid: Int32
    let uid: UInt32
    let gid: UInt32
    let architecture: String
    let operatingSystemVersion: String

    static func current() -> RuntimeIdentity {
        let environment = RuntimeEnvironment.current()
        return RuntimeIdentity(
            pid: getpid(),
            uid: getuid(),
            gid: getgid(),
            architecture: environment.architecture,
            operatingSystemVersion: environment.operatingSystemVersion
        )
    }
}

enum DaemonSpikeEvidenceEvent: Equatable, Sendable {
    case runtimeStarted(RuntimeIdentity)
    case candidateSelected(HIDDeviceDescriptor, score: Int)
    case candidateUnavailable
    case hidOpened(registryID: UInt64)
    case hidOpenFailed(registryID: UInt64, code: Int32)
    case streamStartFailed
    case firstValidReport(angle: Int, count: UInt64)
    case reportMilestone(angle: Int, count: UInt64)
    case powerObserverRegistered
    case powerObserverRegistrationFailed(String)
    case power(SystemPowerEvent)
    case stopping(reason: String)
}

protocol DaemonSpikeEvidenceSinking: Sendable {
    func emit(_ event: DaemonSpikeEvidenceEvent)
    func emitPolicyLine(_ line: String)
}

extension DaemonSpikeEvidenceSinking {
    func emitPolicyLine(_ line: String) {}
}

struct DaemonSpikeEvidenceFormatter: Sendable {
    let timestampFormatter: @Sendable (Date) -> String
    let pid: Int32

    init(
        timestampFormatter: @escaping @Sendable (Date) -> String = { date in
            ISO8601DateFormatter().string(from: date)
        },
        pid: Int32 = getpid()
    ) {
        self.timestampFormatter = timestampFormatter
        self.pid = pid
    }

    func line(for event: DaemonSpikeEvidenceEvent, at date: Date) -> String {
        let prefix = "timestamp=\(timestampFormatter(date))"
        switch event {
        case let .runtimeStarted(identity):
            return "\(prefix) event=runtime-started pid=\(identity.pid) uid=\(identity.uid) gid=\(identity.gid) architecture=\(identity.architecture) macos=\(identity.operatingSystemVersion)"
        case let .candidateSelected(descriptor, score):
            return "\(prefix) event=candidate-selected pid=\(pid) registryID=\(descriptor.registryEntryID) score=\(score) vendorID=\(hex(descriptor.vendorID)) productID=\(hex(descriptor.productID)) usagePage=\(hex(descriptor.usagePage)) usage=\(hex(descriptor.usage)) transport=\(descriptor.transport ?? "unknown")"
        case .candidateUnavailable:
            return "\(prefix) event=candidate-unavailable pid=\(pid)"
        case let .hidOpened(registryID):
            return "\(prefix) event=hid-opened pid=\(pid) registryID=\(registryID)"
        case let .hidOpenFailed(registryID, code):
            return "\(prefix) event=hid-open-failed pid=\(pid) registryID=\(registryID) code=\(code)"
        case .streamStartFailed:
            return "\(prefix) event=stream-start-failed pid=\(pid)"
        case let .firstValidReport(angle, count):
            return "\(prefix) event=first-valid-report pid=\(pid) angle=\(angle) count=\(count)"
        case let .reportMilestone(angle, count):
            return "\(prefix) event=report-milestone pid=\(pid) angle=\(angle) count=\(count)"
        case .powerObserverRegistered:
            return "\(prefix) event=power-observer-registered pid=\(pid)"
        case let .powerObserverRegistrationFailed(error):
            return "\(prefix) event=power-observer-registration-failed pid=\(pid) error=\(error)"
        case let .power(event):
            return "\(prefix) event=power pid=\(pid) power=\(powerName(event))"
        case let .stopping(reason):
            return "\(prefix) event=stopping pid=\(pid) reason=\(reason)"
        }
    }

    private func hex(_ value: Int?) -> String {
        guard let value else { return "unknown" }
        return String(format: "0x%04X", value)
    }

    private func powerName(_ event: SystemPowerEvent) -> String {
        switch event {
        case .canSleep: return "can-sleep"
        case .willSleep: return "will-sleep"
        case .willPowerOn: return "will-power-on"
        case .hasPoweredOn: return "has-powered-on"
        }
    }
}

final class StandardDaemonEvidenceSink: DaemonSpikeEvidenceSinking, @unchecked Sendable {
    private let formatter: DaemonSpikeEvidenceFormatter
    private let now: @Sendable () -> Date
    private let write: @Sendable (Data) -> Void
    private let lock = NSLock()

    init(
        formatter: DaemonSpikeEvidenceFormatter = DaemonSpikeEvidenceFormatter(),
        now: @escaping @Sendable () -> Date = Date.init,
        write: @escaping @Sendable (Data) -> Void = { data in
            FileHandle.standardOutput.write(data)
        }
    ) {
        self.formatter = formatter
        self.now = now
        self.write = write
    }

    func emit(_ event: DaemonSpikeEvidenceEvent) {
        writeLine(formatter.line(for: event, at: now()))
    }

    func emitPolicyLine(_ line: String) {
        writeLine(line)
    }

    private func writeLine(_ line: String) {
        let data = Data((line + "\n").utf8)
        lock.withLock { write(data) }
    }
}

final class DaemonSpikeReportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let sink: DaemonSpikeEvidenceSinking
    private var count: UInt64 = 0

    init(sink: DaemonSpikeEvidenceSinking) {
        self.sink = sink
    }

    func record(angle: Int) {
        let event = lock.withLock { () -> DaemonSpikeEvidenceEvent? in
            guard count < UInt64.max else { return nil }
            count += 1
            if count == 1 { return .firstValidReport(angle: angle, count: count) }
            if count.isMultiple(of: 100) { return .reportMilestone(angle: angle, count: count) }
            return nil
        }
        if let event { sink.emit(event) }
    }
}

struct EvidenceRecordingLidAngleDecoder: LidAngleDecoding {
    let base: LidAngleDecoding
    let recorder: DaemonSpikeReportRecorder

    func decode(_ report: HIDReport) -> AngleDecodeResult {
        let result = base.decode(report)
        if case let .decoded(value) = result,
           value.isFinite,
           value.rounded() == value,
           let angle = Int(exactly: value) {
            recorder.record(angle: angle)
        }
        return result
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
