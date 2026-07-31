import Dispatch
import Darwin
import Foundation

nonisolated(unsafe) private var daemonSignalWriteFD: Int32 = -1

private func daemonSignalHandler(_ signalNumber: Int32) {
    guard daemonSignalWriteFD >= 0 else { return }
    var byte = UInt8(truncatingIfNeeded: signalNumber)
    withUnsafePointer(to: &byte) { pointer in
        _ = Darwin.write(daemonSignalWriteFD, pointer, 1)
    }
}

final class ProcessSignalController: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "macbook-lid-monitor.daemon-signals")
    private var source: DispatchSourceRead?
    private var readFD: Int32 = -1
    private var writeFD: Int32 = -1
    private var handler: (@Sendable () -> Void)?
    private var started = false
    private var finished = false

    func start(onSignal: @escaping @Sendable () -> Void) throws {
        try lock.withLock {
            guard !started else { return }
            var descriptors: [Int32] = [0, 0]
            let result = descriptors.withUnsafeMutableBufferPointer { buffer in
                pipe(buffer.baseAddress!)
            }
            guard result == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            readFD = descriptors[0]
            writeFD = descriptors[1]
            handler = onSignal
            started = true
            finished = false
            daemonSignalWriteFD = writeFD

            let activeSource = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: queue)
            activeSource.setCancelHandler {
                Darwin.close(descriptors[0])
                Darwin.close(descriptors[1])
            }
            activeSource.setEventHandler { [weak self] in
                guard let self else { return }
                var bytes = [UInt8](repeating: 0, count: 8)
                _ = bytes.withUnsafeMutableBytes { buffer in
                    Darwin.read(self.readFD, buffer.baseAddress, buffer.count)
                }
                self.finish(invokeHandler: true)
            }
            source = activeSource
            signal(SIGTERM, daemonSignalHandler)
            signal(SIGINT, daemonSignalHandler)
            activeSource.resume()
        }
    }

    func finishForTesting() {
        finish(invokeHandler: true)
    }

    func stop() {
        finish(invokeHandler: false)
    }

    private func finish(invokeHandler: Bool) {
        let resources = lock.withLock { () -> (DispatchSourceRead?, Int32, Int32, (@Sendable () -> Void)?)? in
            guard started, !finished else { return nil }
            finished = true
            started = false
            daemonSignalWriteFD = -1
            let result = (source, readFD, writeFD, invokeHandler ? handler : nil)
            source = nil
            readFD = -1
            writeFD = -1
            handler = nil
            return result
        }
        guard let resources else { return }
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        resources.0?.cancel()
        resources.3?()
        signal(SIGTERM, SIG_DFL)
        signal(SIGINT, SIG_DFL)
    }

    deinit { stop() }
}
