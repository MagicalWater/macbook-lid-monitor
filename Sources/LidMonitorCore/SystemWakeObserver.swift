import Foundation

protocol SystemWakeObserving: AnyObject, Sendable {
    func start(onWake: @escaping @Sendable (Date) -> Void) throws
    func stop()
}

final class IOKitSystemWakeObserver: SystemWakeObserving, @unchecked Sendable {
    private let powerObserver: SystemPowerObserving
    private let onPowerEvent: @Sendable (SystemPowerEvent) -> Void
    private let onRegistered: @Sendable () -> Void

    init(
        powerObserver: SystemPowerObserving = IOKitSystemPowerObserver(),
        onPowerEvent: @escaping @Sendable (SystemPowerEvent) -> Void = { _ in },
        onRegistered: @escaping @Sendable () -> Void = {}
    ) {
        self.powerObserver = powerObserver
        self.onPowerEvent = onPowerEvent
        self.onRegistered = onRegistered
    }

    func start(onWake: @escaping @Sendable (Date) -> Void) throws {
        try powerObserver.start { [onPowerEvent] event, date in
            onPowerEvent(event)
            guard event == .hasPoweredOn else { return }
            onWake(date)
        }
        onRegistered()
    }

    func stop() {
        powerObserver.stop()
    }
}
