import Foundation

enum HIDInputClass: Equatable, Sendable {
    case keyboard
    case keypad
    case mouse
    case pointer
    case trackpad
    case digitizer
    case consumerControl
    case other
}

struct HIDDeviceDescriptor: Equatable, Sendable {
    let registryEntryID: UInt64
    let name: String
    let vendorID: Int?
    let productID: Int?
    let usagePage: Int?
    let usage: Int?
    let transport: String?
    let inputClass: HIDInputClass
}

struct CandidateScore: Equatable, Sendable {
    let descriptor: HIDDeviceDescriptor
    let score: Int
    let reasons: [String]
}

protocol HIDDeviceEnumerating {
    func descriptors() throws -> [HIDDeviceDescriptor]
}
