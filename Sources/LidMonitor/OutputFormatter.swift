import Foundation

struct OutputFormatter: Sendable {
    private let timeZone: TimeZone

    init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    func environmentLines(_ environment: RuntimeEnvironment) -> [String] {
        [
            "macbook-lid-monitor \(environment.appVersion)",
            "Architecture: \(environment.architecture)",
            "macOS: \(environment.operatingSystemVersion)"
        ]
    }

    func candidateLine(_ candidate: CandidateScore, selectable: Bool) -> String {
        let descriptor = candidate.descriptor
        return [
            "score=\(candidate.score)",
            "selectable=\(selectable ? "yes" : "no")",
            "name=\(descriptor.name)",
            "registryID=\(descriptor.registryEntryID)",
            "vendorID=\(hex(descriptor.vendorID, width: 4))",
            "productID=\(hex(descriptor.productID, width: 4))",
            "usagePage=\(hex(descriptor.usagePage, width: 4))",
            "usage=\(hex(descriptor.usage, width: 4))",
            "transport=\(descriptor.transport ?? "unknown")",
            "reasons=\(candidate.reasons.joined(separator: ","))"
        ].joined(separator: " ")
    }

    func autoSleepLine(_ event: AutoSleepOperationalEvent) -> String {
        switch event {
        case .wouldSleep:
            return "auto-sleep: would-sleep"
        case .sleepRequested:
            return "auto-sleep: sleep-requested"
        case let .sleepRequestFailed(description):
            return "auto-sleep: sleep-request-failed error=\(description)"
        }
    }

    func autoSleepConfigurationLine(
        executionMode: AutoSleepExecutionMode,
        policy: LidSleepPolicy
    ) -> String {
        let mode = switch executionMode {
        case .dryRun: "dry-run"
        case .executeSleep: "execute-sleep"
        }
        return [
            "auto-sleep config:",
            "mode=\(mode)",
            "sleep-threshold=\(policy.sleepThreshold)",
            "reopen-threshold=\(policy.reopenThreshold)",
            "debounce=\(number(policy.closeDebounce))",
            "startup-cooldown=\(number(policy.startupCooldown))",
            "wake-recovery=\(number(policy.wakeRecovery))"
        ].joined(separator: " ")
    }

    func autoSleepTransitionLine(_ event: AutoSleepTransitionEvent) -> String {
        let value: String
        switch event {
        case .rearmed: value = "rearmed"
        case .candidateStarted: value = "candidate-started"
        case .candidateCancelled: value = "candidate-cancelled"
        case .triggered: value = "triggered"
        case .disarmed: value = "disarmed"
        case .startupCooldown: value = "startup-cooldown"
        case .wakeRecovery: value = "wake-recovery"
        case .recoveryResleep: value = "recovery-resleep"
        case .recoverySensorUnavailable: value = "recovery-sensor-unavailable"
        }
        return "auto-sleep: \(value)"
    }

    func watchLine(
        timestamp: Date,
        result: AngleDecodeResult,
        rawBytes: [UInt8]?,
        clamshell: ClamshellState
    ) -> String {
        var fields = [iso8601(timestamp)]

        switch result {
        case .decoded(let angle):
            fields.append(String(format: "angle=%.1f", angle))
        case .unsupported(let reportLength):
            fields.append("angle=unsupported")
            fields.append("reportLength=\(reportLength)")
        case .malformed(let reason):
            fields.append("angle=malformed")
            fields.append("reason=\(quoted(reason))")
        case .outOfRange(let angle):
            fields.append(String(format: "angle=outOfRange(%.1f)", angle))
        }

        if let rawBytes {
            fields.append(
                "raw=" + rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            )
        }

        fields.append("clamshell=\(clamshellText(clamshell))")
        return fields.joined(separator: " ")
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private func clamshellText(_ state: ClamshellState) -> String {
        switch state {
        case .open: "open"
        case .closed: "closed"
        case .unavailable: "unavailable"
        }
    }

    private func hex(_ value: Int?, width: Int) -> String {
        guard let value else { return "unknown" }
        return "0x" + String(format: "%0\(width)X", value)
    }

    private func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func number(_ value: TimeInterval) -> String {
        value.rounded() == value
            ? String(Int(value))
            : String(value)
    }
}
