import CoreFoundation
import Foundation
import IOKit
import IOKit.pwr_mgt

struct SystemPowerMessage {
    static let canSystemSleep: UInt32 = 0xE000_0270
    static let systemWillSleep: UInt32 = 0xE000_0280
    static let systemWillPowerOn: UInt32 = 0xE000_0320
    static let systemHasPoweredOn: UInt32 = 0xE000_0300
}

enum SystemPowerEvent: Equatable, Sendable {
    case canSleep
    case willSleep
    case willPowerOn
    case hasPoweredOn
}

protocol SystemPowerObserving: AnyObject, Sendable {
    func start(
        onEvent: @escaping @Sendable (SystemPowerEvent, Date) -> Void
    ) throws
    func stop()
}

final class SystemPowerRegistration: @unchecked Sendable {
    let rootPort: io_connect_t
    private let lock = NSLock()
    private var cleanupAction: (() -> Void)?

    init(rootPort: io_connect_t, cleanup: @escaping () -> Void = {}) {
        self.rootPort = rootPort
        cleanupAction = cleanup
    }

    func cleanup() {
        let action = lock.withLock { () -> (() -> Void)? in
            defer { cleanupAction = nil }
            return cleanupAction
        }
        action?()
    }
}

protocol SystemPowerNotificationOperating: AnyObject, Sendable {
    func register(
        callback: @escaping @Sendable (UInt32, Int) -> Void
    ) throws -> SystemPowerRegistration
    func allowPowerChange(rootPort: io_connect_t, notificationID: Int)
    func deregister(_ registration: SystemPowerRegistration)
}

enum SystemPowerNotificationError: Error, Equatable {
    case registrationFailed
    case runLoopSourceUnavailable
}

private final class SystemPowerRegistrationHolder: @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value: SystemPowerRegistration?

    func set(_ registration: SystemPowerRegistration) {
        lock.withLock { value = registration }
        ready.signal()
    }

    func get() -> SystemPowerRegistration {
        ready.wait()
        ready.signal()
        return lock.withLock { value! }
    }
}

final class IOKitSystemPowerObserver: SystemPowerObserving, @unchecked Sendable {
    private let operation: SystemPowerNotificationOperating
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var registration: SystemPowerRegistration?

    init(
        operation: SystemPowerNotificationOperating = NativeSystemPowerNotificationOperation(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.operation = operation
        self.now = now
    }

    func start(
        onEvent: @escaping @Sendable (SystemPowerEvent, Date) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard registration == nil else { return }

        let holder = SystemPowerRegistrationHolder()
        let created = try operation.register { [weak self] message, notificationID in
            guard let self else { return }
            let registration = holder.get()
            switch message {
            case SystemPowerMessage.canSystemSleep:
                self.operation.allowPowerChange(
                    rootPort: registration.rootPort,
                    notificationID: notificationID
                )
                onEvent(.canSleep, self.now())
            case SystemPowerMessage.systemWillSleep:
                self.operation.allowPowerChange(
                    rootPort: registration.rootPort,
                    notificationID: notificationID
                )
                onEvent(.willSleep, self.now())
            case SystemPowerMessage.systemWillPowerOn:
                onEvent(.willPowerOn, self.now())
            case SystemPowerMessage.systemHasPoweredOn:
                onEvent(.hasPoweredOn, self.now())
            default:
                break
            }
        }
        holder.set(created)
        registration = created
    }

    func stop() {
        let existing = lock.withLock { () -> SystemPowerRegistration? in
            defer { registration = nil }
            return registration
        }
        if let existing {
            operation.deregister(existing)
        }
    }

    deinit {
        stop()
    }
}

private final class PowerCallbackBox: @unchecked Sendable {
    let callback: @Sendable (UInt32, Int) -> Void

    init(callback: @escaping @Sendable (UInt32, Int) -> Void) {
        self.callback = callback
    }
}

final class NativeSystemPowerNotificationOperation: SystemPowerNotificationOperating, @unchecked Sendable {
    private final class ResultBox: @unchecked Sendable {
        let lock = NSLock()
        var result: Result<SystemPowerRegistration, Error>?
    }

    func register(
        callback: @escaping @Sendable (UInt32, Int) -> Void
    ) throws -> SystemPowerRegistration {
        let ready = DispatchSemaphore(value: 0)
        let resultBox = ResultBox()

        Thread.detachNewThread {
            let callbackBox = PowerCallbackBox(callback: callback)
            var notificationPort: IONotificationPortRef?
            var notificationObject: io_object_t = 0
            let rootPort = IORegisterForSystemPower(
                Unmanaged.passUnretained(callbackBox).toOpaque(),
                &notificationPort,
                { context, _, messageType, messageArgument in
                    guard let context else { return }
                    let box = Unmanaged<PowerCallbackBox>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    box.callback(messageType, Int(bitPattern: messageArgument))
                },
                &notificationObject
            )

            guard rootPort != 0, let notificationPort else {
                resultBox.lock.withLock {
                    resultBox.result = .failure(SystemPowerNotificationError.registrationFailed)
                }
                ready.signal()
                return
            }

            guard let source = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue() else {
                IODeregisterForSystemPower(&notificationObject)
                IOServiceClose(rootPort)
                IONotificationPortDestroy(notificationPort)
                resultBox.lock.withLock {
                    resultBox.result = .failure(SystemPowerNotificationError.runLoopSourceUnavailable)
                }
                ready.signal()
                return
            }

            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            let registration = SystemPowerRegistration(rootPort: rootPort) {
                let finished = DispatchSemaphore(value: 0)
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                    CFRunLoopRemoveSource(runLoop, source, .defaultMode)
                    var object = notificationObject
                    IODeregisterForSystemPower(&object)
                    IOServiceClose(rootPort)
                    IONotificationPortDestroy(notificationPort)
                    CFRunLoopStop(runLoop)
                    finished.signal()
                }
                CFRunLoopWakeUp(runLoop)
                finished.wait()
                _ = callbackBox
            }
            resultBox.lock.withLock { resultBox.result = .success(registration) }
            ready.signal()
            CFRunLoopRun()
        }

        ready.wait()
        return try resultBox.lock.withLock {
            try resultBox.result!.get()
        }
    }

    func allowPowerChange(rootPort: io_connect_t, notificationID: Int) {
        IOAllowPowerChange(rootPort, notificationID)
    }

    func deregister(_ registration: SystemPowerRegistration) {
        registration.cleanup()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
