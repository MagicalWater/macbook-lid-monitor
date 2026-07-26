import Foundation

protocol ProductionEventSinking: Sendable {
    func emit(_ event: ProductionEvent)
}

final class ProductionEventSink: ProductionEventSinking, @unchecked Sendable {
    private let formatter: ProductionEventFormatter
    private let now: @Sendable () -> Date
    private let write: @Sendable (Data) -> Void
    private let lock = NSLock()

    init(
        formatter: ProductionEventFormatter = ProductionEventFormatter(),
        now: @escaping @Sendable () -> Date = Date.init,
        write: @escaping @Sendable (Data) -> Void = { FileHandle.standardOutput.write($0) }
    ) {
        self.formatter = formatter
        self.now = now
        self.write = write
    }

    func emit(_ event: ProductionEvent) {
        let data = Data((formatter.line(for: event, at: now()) + "\n").utf8)
        lock.lock()
        write(data)
        lock.unlock()
    }
}
