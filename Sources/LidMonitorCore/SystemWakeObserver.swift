import Foundation

protocol SystemWakeObserving: AnyObject, Sendable {
    func start(onWake: @escaping @Sendable (Date) -> Void) throws
    func stop()
}

final class IOKitSystemWakeObserver: SystemWakeObserving, @unchecked Sendable {
    private let powerObserver: SystemPowerObserving
    private let onPowerEvent: @Sendable (SystemPowerEvent) -> Void

    init(
        powerObserver: SystemPowerObserving = IOKitSystemPowerObserver(),
        onPowerEvent: @escaping @Sendable (SystemPowerEvent) -> Void = { _ in }
    ) {
        self.powerObserver = powerObserver
        self.onPowerEvent = onPowerEvent
    }

    func start(onWake: @escaping @Sendable (Date) -> Void) throws {
        try powerObserver.start { [onPowerEvent] event, date in
            onPowerEvent(event)
            guard event == .hasPoweredOn else { return }
            onWake(date)
        }
    }

    func stop() {
        powerObserver.stop()
    }
}
