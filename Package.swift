// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SleepManager",
    platforms: [.macOS(.v26)],
    targets: [
        // Parsing and command running, kept free of AppKit so it can be tested.
        .target(name: "SleepCore"),
        .executableTarget(name: "SleepManager", dependencies: ["SleepCore"]),
        .testTarget(name: "SleepCoreTests", dependencies: ["SleepCore"]),
    ]
)
