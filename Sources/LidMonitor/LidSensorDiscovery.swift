import Foundation
import IOKit
import IOKit.hid

struct CandidateRanker {
    static let minimumSelectableScore = 40

    static func rank(_ descriptors: [HIDDeviceDescriptor]) -> [CandidateScore] {
        descriptors
            .filter { !isExcluded($0) }
            .map(score)
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.descriptor.registryEntryID < $1.descriptor.registryEntryID
            }
    }

    private static func isExcluded(_ descriptor: HIDDeviceDescriptor) -> Bool {
        switch descriptor.inputClass {
        case .keyboard, .keypad, .mouse, .pointer, .trackpad, .digitizer, .consumerControl:
            return true
        case .other:
            break
        }

        let normalizedName = descriptor.name.lowercased()
        return ["keyboard", "keypad", "trackpad", "mouse", "pointer", "digitizer"]
            .contains { normalizedName.contains($0) }
    }

    private static func score(_ descriptor: HIDDeviceDescriptor) -> CandidateScore {
        let normalizedName = descriptor.name.lowercased()
        var score = 0
        var reasons: [String] = []

        for token in ["lid", "angle", "hinge", "clamshell"] where containsToken(token, in: normalizedName) {
            score += 30
            reasons.append("name:\(token)=+30")
        }

        if containsToken("sensor", in: normalizedName) {
            score += 10
            reasons.append("name:sensor=+10")
        }

        if let usagePage = descriptor.usagePage, usagePage >= 0xFF00 {
            score += 10
            reasons.append("usagePage:vendorDefined=+10")
        }

        if descriptor.vendorID == 0x05AC {
            score += 5
            reasons.append("vendor:apple=+5")
        }

        if descriptor.vendorID == 0x05AC,
           descriptor.productID == 0x8104,
           descriptor.usagePage == 0x0020,
           descriptor.usage == 0x008A {
            score += 40
            reasons.append("identity:appleHingeOrientation=+40")
        }

        return CandidateScore(descriptor: descriptor, score: score, reasons: reasons)
    }

    private static func containsToken(_ token: String, in value: String) -> Bool {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .contains(token)
    }
}

enum HIDEnumerationError: Error, Equatable {
    case copyDevicesFailed
}

final class IOHIDDeviceEnumerator: HIDDeviceEnumerating {
    func descriptors() throws -> [HIDDeviceDescriptor] {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )

        IOHIDManagerSetDeviceMatching(manager, nil)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            throw HIDEnumerationError.copyDevicesFailed
        }

        return devices.map(descriptor)
    }

    private func descriptor(for device: IOHIDDevice) -> HIDDeviceDescriptor {
        let usagePage = intProperty(kIOHIDPrimaryUsagePageKey, device: device)
        let usage = intProperty(kIOHIDPrimaryUsageKey, device: device)

        return HIDDeviceDescriptor(
            registryEntryID: registryEntryID(for: device),
            name: stringProperty(kIOHIDProductKey, device: device)
                ?? stringProperty(kIOHIDManufacturerKey, device: device)
                ?? "Unknown HID Device",
            vendorID: intProperty(kIOHIDVendorIDKey, device: device),
            productID: intProperty(kIOHIDProductIDKey, device: device),
            usagePage: usagePage,
            usage: usage,
            transport: stringProperty(kIOHIDTransportKey, device: device),
            inputClass: classify(usagePage: usagePage, usage: usage)
        )
    }

    private func intProperty(_ key: String, device: IOHIDDevice) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    private func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func registryEntryID(for device: IOHIDDevice) -> UInt64 {
        var entryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        guard service != 0, IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else {
            return 0
        }
        return entryID
    }

    private func classify(usagePage: Int?, usage: Int?) -> HIDInputClass {
        guard let usagePage else {
            return .other
        }

        switch usagePage {
        case 0x07:
            return .keyboard
        case 0x0C:
            return .consumerControl
        case 0x0D:
            if usage == 0x05 {
                return .trackpad
            }
            return .digitizer
        case 0x01:
            switch usage {
            case 0x01: return .pointer
            case 0x02: return .mouse
            case 0x06: return .keyboard
            case 0x07: return .keypad
            default: return .other
            }
        default:
            return .other
        }
    }
}
