import Foundation
import IOKit
import IOKit.hid

protocol HIDReportStreaming: AnyObject {
    func start(onReport: @escaping @Sendable (HIDReport) -> Void) throws
    func stop()
}

protocol HIDDeviceSession: AnyObject, Sendable {
    func open() throws
    func registerInputCallback(
        _ callback: @escaping @Sendable (UInt32, [UInt8]) -> Void
    ) throws
    func run()
    func stop()
    func close()
}

enum HIDReportStreamError: Error, Equatable {
    case deviceNotFound(UInt64)
    case openFailed(IOReturn)
    case invalidBufferSize(Int)
}

final class IOHIDReportStream: HIDReportStreaming, @unchecked Sendable {
    private let session: HIDDeviceSession
    private let runAsynchronously: Bool
    private let lock = NSLock()
    private var started = false
    private var stopped = false

    convenience init(descriptor: HIDDeviceDescriptor) throws {
        try self.init(
            session: NativeHIDDeviceSession(descriptor: descriptor),
            runAsynchronously: true
        )
    }

    init(session: HIDDeviceSession, runAsynchronously: Bool) {
        self.session = session
        self.runAsynchronously = runAsynchronously
    }

    func start(onReport: @escaping @Sendable (HIDReport) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !started else { return }
        try session.open()
        do {
            try session.registerInputCallback { reportID, bytes in
                onReport(
                    HIDReport(
                        reportID: reportID,
                        bytes: bytes,
                        timestamp: Date()
                    )
                )
            }
        } catch {
            session.close()
            throw error
        }

        started = true
        if runAsynchronously {
            Thread.detachNewThread { [session] in
                session.run()
            }
        } else {
            session.run()
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard started, !stopped else { return }
        stopped = true
        session.stop()
        session.close()
    }

    deinit {
        stop()
    }
}

private final class NativeHIDDeviceSession: HIDDeviceSession, @unchecked Sendable {
    private static let fallbackBufferSize = 64
    private static let maximumBufferSize = 4096

    private let device: IOHIDDevice
    private var callbackBox: CallbackBox?
    private var reportBuffer: [UInt8] = []
    private var runLoop: CFRunLoop?
    private let stateLock = NSLock()
    private var isOpen = false
    private var stopRequested = false

    init(descriptor: HIDDeviceDescriptor) throws {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, nil)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let matched = devices.first(where: {
                  Self.registryEntryID(for: $0) == descriptor.registryEntryID
              }) else {
            throw HIDReportStreamError.deviceNotFound(descriptor.registryEntryID)
        }
        device = matched
    }

    func open() throws {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw HIDReportStreamError.openFailed(result)
        }
        stateLock.withLock { isOpen = true }
    }

    func registerInputCallback(
        _ callback: @escaping @Sendable (UInt32, [UInt8]) -> Void
    ) throws {
        let property = IOHIDDeviceGetProperty(
            device,
            kIOHIDMaxInputReportSizeKey as CFString
        ) as? NSNumber
        let requested = property?.intValue ?? Self.fallbackBufferSize
        guard requested > 0, requested <= Self.maximumBufferSize else {
            throw HIDReportStreamError.invalidBufferSize(requested)
        }

        reportBuffer = Array(repeating: 0, count: requested)
        let box = CallbackBox(callback: callback)
        callbackBox = box
        let context = Unmanaged.passUnretained(box).toOpaque()

        reportBuffer.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?
                .assumingMemoryBound(to: UInt8.self) else { return }
            IOHIDDeviceRegisterInputReportCallback(
                device,
                baseAddress,
                requested,
                { context, result, _, _, reportID, report, reportLength in
                    guard result == kIOReturnSuccess,
                          let context else { return }
                    let box = Unmanaged<CallbackBox>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    let bytes = Array(
                        UnsafeBufferPointer(start: report, count: reportLength)
                    )
                    box.callback(reportID, bytes)
                },
                context
            )
        }
    }

    func run() {
        let shouldRun = stateLock.withLock { !stopRequested }
        guard shouldRun else { return }

        guard let current = CFRunLoopGetCurrent() else { return }
        stateLock.withLock { runLoop = current }
        IOHIDDeviceScheduleWithRunLoop(device, current, CFRunLoopMode.defaultMode.rawValue)
        CFRunLoopRun()
        IOHIDDeviceUnscheduleFromRunLoop(device, current, CFRunLoopMode.defaultMode.rawValue)
        stateLock.withLock { runLoop = nil }
    }

    func stop() {
        let activeRunLoop = stateLock.withLock { () -> CFRunLoop? in
            stopRequested = true
            return runLoop
        }
        if let activeRunLoop {
            CFRunLoopStop(activeRunLoop)
        }
    }

    func close() {
        let shouldClose = stateLock.withLock { () -> Bool in
            guard isOpen else { return false }
            isOpen = false
            return true
        }
        if shouldClose {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private static func registryEntryID(for device: IOHIDDevice) -> UInt64 {
        var entryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        guard service != 0,
              IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else {
            return 0
        }
        return entryID
    }
}

private final class CallbackBox: @unchecked Sendable {
    let callback: @Sendable (UInt32, [UInt8]) -> Void

    init(callback: @escaping @Sendable (UInt32, [UInt8]) -> Void) {
        self.callback = callback
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
