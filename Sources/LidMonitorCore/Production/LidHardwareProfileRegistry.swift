import Foundation

struct LidHardwareProfileRegistry: Sendable {
    static let production = LidHardwareProfileRegistry(
        profiles: [
            LidHardwareProfile(
                id: "m1-pro-0x8104-report-id-1-v1",
                vendorID: 0x05AC,
                productID: 0x8104,
                usagePage: 0x0020,
                usage: 0x008A,
                transport: "SPU",
                decoderKind: .reportID1Degrees
            )
        ]
    )

    let profiles: [LidHardwareProfile]

    func resolve(
        profileID: String,
        descriptors: [HIDDeviceDescriptor]
    ) throws -> ResolvedLidHardwareProfile {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            throw LidHardwareProfileError.unknownProfile(profileID)
        }
        let matches = descriptors.filter(profile.matches)
        guard !matches.isEmpty else {
            throw LidHardwareProfileError.noExactDeviceMatch
        }
        guard matches.count == 1, let descriptor = matches.first else {
            throw LidHardwareProfileError.ambiguousExactDeviceMatch(matches.count)
        }
        return ResolvedLidHardwareProfile(
            profile: profile,
            descriptor: descriptor,
            decoder: profile.makeDecoder()
        )
    }
}
