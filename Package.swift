// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macbook-lid-monitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macbook-lid-monitor", targets: ["LidMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "LidMonitor",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "LidMonitorTests",
            dependencies: ["LidMonitor"]
        )
    ]
)
