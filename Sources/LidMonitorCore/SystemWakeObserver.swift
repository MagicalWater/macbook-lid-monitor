import Foundation

protocol SystemWakeObserving: AnyObject, Sendable {
    func start(onWake: @escaping @Sendable (Date) -> Void) throws
    func stop()
}

final class IOKitSystemWakeObserver: SystemWakeObserving, @unchecked Sendable {
    private let powerObserver: SystemPowerObserving

    init(powerObserver: SystemPowerObserving = IOKitSystemPowerObserver()) {
        self.powerObserver = powerObserver
    }

    func start(onWake: @escaping @Sendable (Date) -> Void) throws {
        try powerObserver.start { event, date in
            guard event == .hasPoweredOn else { return }
            onWake(date)
        }
    }

    func stop() {
        powerObserver.stop()
    }
}
