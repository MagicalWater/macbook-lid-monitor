import Foundation

struct RuntimeEnvironment: Equatable, Sendable {
    let appVersion: String
    let architecture: String
    let operatingSystemVersion: String

    static func current() -> RuntimeEnvironment {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let operatingSystemVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        return RuntimeEnvironment(
            appVersion: AppVersion.current,
            architecture: architecture,
            operatingSystemVersion: operatingSystemVersion
        )
    }
}
