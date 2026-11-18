// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PS4LinuxTools",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PS4LinuxCore", targets: ["PS4LinuxCore"]),
        .executable(name: "ps4-linux-test", targets: ["ps4-linux-test"]),
        .executable(name: "ps4-linux-layout-check", targets: ["ps4-linux-layout-check"]),
        .executable(name: "ps4-linux-install-guard", targets: ["ps4-linux-install-guard"]),
    ],
    targets: [
        .target(name: "PS4LinuxCore"),
        .testTarget(name: "PS4LinuxCoreTests", dependencies: ["PS4LinuxCore"]),
        .executableTarget(name: "ps4-linux-test", dependencies: ["PS4LinuxCore"]),
        .executableTarget(name: "ps4-linux-layout-check", dependencies: ["PS4LinuxCore"]),
        .executableTarget(name: "ps4-linux-install-guard", dependencies: ["PS4LinuxCore"]),
    ]
)
