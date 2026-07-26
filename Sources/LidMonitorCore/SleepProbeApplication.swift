import Foundation

struct SleepProbeApplication {
    static let approvalToken = "I-APPROVE-ONE-DAEMON-SLEEP"

    private let operation: SystemSleepOperating
    private let output: @Sendable (String) -> Void

    init(
        operation: SystemSleepOperating,
        output: @escaping @Sendable (String) -> Void
    ) {
        self.operation = operation
        self.output = output
    }

    func run(arguments: [String]) -> Int32 {
        switch arguments {
        case ["--dry-run"]:
            output("sleep-probe: would-request-sleep")
            return ExitCode.success.rawValue

        case ["--execute-once", "--approval-token", Self.approvalToken]:
            do {
                try operation.requestSleep()
                output("sleep-probe: sleep-requested")
                return ExitCode.success.rawValue
            } catch {
                output(
                    "sleep-probe: sleep-request-failed error="
                        + stableSleepErrorDescription(error)
                )
                return ExitCode.internalError.rawValue
            }

        default:
            output(
                "usage: macbook-lid-monitor-sleep-probe --dry-run | "
                    + "--execute-once --approval-token <token>"
            )
            return ExitCode.usage.rawValue
        }
    }
}

public enum LidMonitorSleepProbeEntryPoint {
    public static func run(arguments: [String]) -> Int32 {
        let application = SleepProbeApplication(
            operation: IOKitSystemSleepOperation(),
            output: { line in
                FileHandle.standardOutput.write(Data((line + "\n").utf8))
            }
        )
        return application.run(arguments: arguments)
    }
}
