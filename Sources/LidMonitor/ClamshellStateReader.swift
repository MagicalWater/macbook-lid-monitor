import Foundation
import IOKit
import IOKit.pwr_mgt

protocol ClamshellStateReading {
    func currentState() -> ClamshellState
}

final class IORegistryClamshellStateReader: ClamshellStateReading {
    func currentState() -> ClamshellState {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else {
            return .unavailable
        }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            return .unavailable
        }

        return value.boolValue ? .closed : .open
    }
}
