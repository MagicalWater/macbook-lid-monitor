import AppKit
import Foundation

protocol SystemWakeObserving: AnyObject, Sendable {
    func start(onWake: @escaping @Sendable (Date) -> Void)
    func stop()
}

final class WorkspaceSystemWakeObserver: SystemWakeObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    func start(onWake: @escaping @Sendable (Date) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard observer == nil else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { _ in
            onWake(Date())
        }
    }

    func stop() {
        let existing: NSObjectProtocol?
        lock.lock()
        existing = observer
        observer = nil
        lock.unlock()

        if let existing {
            NSWorkspace.shared.notificationCenter.removeObserver(existing)
        }
    }

    deinit {
        stop()
    }
}
