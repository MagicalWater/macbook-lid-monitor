import Dispatch
import Darwin
import Foundation

nonisolated(unsafe) private var autoSleepSignalWriteFD: Int32 = -1

private func autoSleepSignalHandler(_ signalNumber: Int32) {
    guard autoSleepSignalWriteFD >= 0 else { return }
    var byte = UInt8(truncatingIfNeeded: signalNumber)
    withUnsafePointer(to: &byte) { pointer in
        _ = Darwin.write(autoSleepSignalWriteFD, pointer, 1)
    }
}

enum AutoSleepComposition {
    static func makeCoordinator(
        stream: HIDReportStreaming,
        decoder: LidAngleDecoding,
        scheduler: OneShotScheduling,
        wakeObserver: SystemWakeObserving,
        executionMode: AutoSleepExecutionMode,
        policy: LidSleepPolicy,
        now: @escaping @Sendable () -> Date = Date.init,
        systemSleepOperation: (any SystemSleepOperating)? = nil,
        onOperationalEvent: @escaping @Sendable (AutoSleepOperationalEvent) -> Void
    ) -> LidSleepCoordinator {
        let requester: any SleepRequesting

        switch executionMode {
        case .dryRun:
            requester = DryRunSleepRequester(onEvent: onOperationalEvent)
        case .executeSleep:
            requester = ReportingSleepRequester(
                requester: MacOSSleepRequester(
                    operation: systemSleepOperation ?? IOKitSystemSleepOperation()
                ),
                onEvent: onOperationalEvent
            )
        }

        return LidSleepCoordinator(
            stream: stream,
            decoder: decoder,
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            sleepRequester: requester,
            policy: policy,
            now: now
        )
    }
}

private final class ReportingSleepRequester: SleepRequesting, @unchecked Sendable {
    let requester: any SleepRequesting
    let onEvent: @Sendable (AutoSleepOperationalEvent) -> Void

    init(
        requester: any SleepRequesting,
        onEvent: @escaping @Sendable (AutoSleepOperationalEvent) -> Void
    ) {
        self.requester = requester
        self.onEvent = onEvent
    }

    func requestSleep() throws {
        try requester.requestSleep()
        onEvent(.sleepRequested)
    }
}

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

private final class AutoSleepRunController: @unchecked Sendable {
    private let lock = NSLock()
    private let coordinator: LidSleepCoordinator
    private let mainRunLoop: CFRunLoop
    private let signalQueue = DispatchQueue(label: "macbook-lid-monitor.signals")
    private var signalSource: DispatchSourceRead?
    private var signalReadFD: Int32 = -1
    private var signalWriteFD: Int32 = -1
    private var finished = false

    init(coordinator: LidSleepCoordinator) {
        self.coordinator = coordinator
        mainRunLoop = CFRunLoopGetMain()
    }

    func startSignalHandling() throws {
        var descriptors: [Int32] = [0, 0]
        let pipeResult = descriptors.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return Int32(-1) }
            return pipe(baseAddress)
        }
        guard pipeResult == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let readFD = descriptors[0]
        let writeFD = descriptors[1]
        let source = DispatchSource.makeReadSource(
            fileDescriptor: readFD,
            queue: signalQueue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 8)
            _ = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(readFD, bytes.baseAddress, bytes.count)
            }
            self.finish()
        }

        lock.withLock {
            signalReadFD = readFD
            signalWriteFD = writeFD
            signalSource = source
            autoSleepSignalWriteFD = writeFD
        }

        signal(SIGINT, autoSleepSignalHandler)
        signal(SIGTERM, autoSleepSignalHandler)
        source.resume()
    }

    func finish() {
        let resources = lock.withLock { () -> (DispatchSourceRead?, Int32, Int32)? in
            guard !finished else { return nil }
            finished = true
            let activeSource = signalSource
            let readFD = signalReadFD
            let writeFD = signalWriteFD
            signalSource = nil
            signalReadFD = -1
            signalWriteFD = -1
            autoSleepSignalWriteFD = -1
            return (activeSource, readFD, writeFD)
        }
        guard let resources else { return }
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)
        resources.0?.cancel()
        if resources.1 >= 0 { close(resources.1) }
        if resources.2 >= 0 { close(resources.2) }
        coordinator.stop()
        CFRunLoopPerformBlock(
            mainRunLoop,
            CFRunLoopMode.defaultMode.rawValue
        ) { [mainRunLoop] in
            CFRunLoopStop(mainRunLoop)
        }
        CFRunLoopWakeUp(mainRunLoop)
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

        switch options.mode {
        case .list:
            return .success
        case .watch:
            return try runWatch(
                descriptor: selected.descriptor,
                options: options
            )
        case let .autoSleep(executionMode, policy):
            return try runAutoSleep(
                descriptor: selected.descriptor,
                executionMode: executionMode,
                policy: policy
            )
        }
    }

    private func runWatch(
        descriptor: HIDDeviceDescriptor,
        options: CLIOptions
    ) throws -> ExitCode {

        let stream = try IOHIDReportStream(descriptor: descriptor)
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

    private func runAutoSleep(
        descriptor: HIDDeviceDescriptor,
        executionMode: AutoSleepExecutionMode,
        policy: LidSleepPolicy
    ) throws -> ExitCode {
        let stream = try IOHIDReportStream(descriptor: descriptor)
        let activeFormatter = formatter
        let coordinator = AutoSleepComposition.makeCoordinator(
            stream: stream,
            decoder: decoder,
            scheduler: DispatchOneShotScheduler(),
            wakeObserver: WorkspaceSystemWakeObserver(),
            executionMode: executionMode,
            policy: policy,
            onOperationalEvent: { event in
                print(activeFormatter.autoSleepLine(event))
            }
        )
        let controller = AutoSleepRunController(coordinator: coordinator)

        try controller.startSignalHandling()

        do {
            try coordinator.start()
            CFRunLoopRun()
        } catch {
            controller.finish()
            throw error
        }

        controller.finish()
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
