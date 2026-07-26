import Dispatch
import Foundation

private final class FinishController: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let stream: HIDReportStreaming
    private var finished = false

    init(stream: HIDReportStreaming) {
        self.stream = stream
    }

    func finish() {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !finished else { return false }
            finished = true
            return true
        }
        guard shouldFinish else { return }
        stream.stop()
        semaphore.signal()
    }

    func wait() {
        semaphore.wait()
    }
}

private struct DiagnosticApplication {
    let enumerator: HIDDeviceEnumerating
    let formatter: OutputFormatter
    let decoder: LidAngleDecoding
    let clamshellReader: ClamshellStateReading

    func run(options: CLIOptions) throws -> ExitCode {
        formatter.environmentLines(.current()).forEach { print($0) }

        let descriptors = try enumerator.descriptors()
        let ranked = CandidateRanker.rank(descriptors)
        print("Candidates found: \(ranked.count)")

        for candidate in ranked {
            print(
                formatter.candidateLine(
                    candidate,
                    selectable: candidate.score >= CandidateRanker.minimumSelectableScore
                )
            )
        }

        guard let selected = ranked.first,
              selected.score >= CandidateRanker.minimumSelectableScore else {
            return .unavailable
        }

        guard options.mode == .watch else {
            return .success
        }

        let stream = try IOHIDReportStream(descriptor: selected.descriptor)
        let controller = FinishController(stream: stream)
        let activeDecoder = decoder
        let activeFormatter = formatter
        let activeClamshellReader = clamshellReader
        let includeRaw = options.includeRaw

        try stream.start { report in
            let result = activeDecoder.decode(report)
            let raw = includeRaw ? report.bytes : nil
            print(
                activeFormatter.watchLine(
                    timestamp: report.timestamp,
                    result: result,
                    rawBytes: raw,
                    clamshell: activeClamshellReader.currentState()
                )
            )
        }

        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT)
        signalSource.setEventHandler { controller.finish() }
        signalSource.resume()

        if let duration = options.duration {
            DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
                controller.finish()
            }
        }

        controller.wait()
        signalSource.cancel()
        return .success
    }
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let exitCode: ExitCode
do {
    let options = try CLIParser.parse(Array(CommandLine.arguments.dropFirst()))
    let application = DiagnosticApplication(
        enumerator: IOHIDDeviceEnumerator(),
        formatter: OutputFormatter(),
        decoder: CompositeLidAngleDecoder(
            decoders: [ReportID1DegreesDecoder(), UInt16TenthsDecoder()]
        ),
        clamshellReader: IORegistryClamshellStateReader()
    )
    exitCode = try application.run(options: options)
} catch let error as CLIParseError {
    writeError("usage error: \(error)")
    exitCode = .usage
} catch let error as HIDReportStreamError {
    writeError("HID I/O error: \(error)")
    exitCode = .ioFailure
} catch let error as HIDEnumerationError {
    writeError("HID unavailable: \(error)")
    exitCode = .unavailable
} catch {
    writeError("internal error: \(error)")
    exitCode = .internalError
}

exit(exitCode.rawValue)

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
