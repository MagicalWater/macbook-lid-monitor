// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macbook-lid-monitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macbook-lid-monitor", targets: ["LidMonitorCLI"]),
        .executable(name: "macbook-lid-monitor-daemon-spike", targets: ["LidMonitorDaemonSpike"]),
        .executable(name: "macbook-lid-monitor-sleep-probe", targets: ["LidMonitorSleepProbe"])
    ],
    targets: [
        .target(
            name: "LidMonitorCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(name: "LidMonitorCLI", dependencies: ["LidMonitorCore"]),
        .executableTarget(name: "LidMonitorDaemonSpike", dependencies: ["LidMonitorCore"]),
        .executableTarget(name: "LidMonitorSleepProbe", dependencies: ["LidMonitorCore"]),
        .testTarget(name: "LidMonitorTests", dependencies: ["LidMonitorCore"])
    ]
)
