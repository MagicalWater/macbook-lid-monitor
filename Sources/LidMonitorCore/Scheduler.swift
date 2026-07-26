import Dispatch
import Foundation

protocol CancellableTask: Sendable {
    func cancel()
}

protocol OneShotScheduling: Sendable {
    func schedule(
        at deadline: Date,
        _ action: @escaping @Sendable () -> Void
    ) -> CancellableTask
}

struct DispatchOneShotScheduler: OneShotScheduling {
    let queue: DispatchQueue

    init(queue: DispatchQueue = .global(qos: .utility)) {
        self.queue = queue
    }

    func schedule(
        at deadline: Date,
        _ action: @escaping @Sendable () -> Void
    ) -> CancellableTask {
        let workItem = DispatchWorkItem(block: action)
        let delay = max(0, deadline.timeIntervalSinceNow)
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        return DispatchCancellableTask(workItem: workItem)
    }
}

private final class DispatchCancellableTask: CancellableTask, @unchecked Sendable {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}
