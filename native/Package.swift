// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RELAY",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "RelayCore", targets: ["RelayCore"]),
               .executable(name: "RelayLab", targets: ["RelayLab"]),
               .executable(name: "RelayCloudCheck", targets: ["RelayCloudCheck"]),
               .executable(name: "RelayWorkflowCheck", targets: ["RelayWorkflowCheck"]),
               .executable(name: "RelaySpeechCheck", targets: ["RelaySpeechCheck"]),
               .executable(name: "RelayNearbyCheck", targets: ["RelayNearbyCheck"])],
    targets: [
        .target(name: "RelayCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "RelayLab", dependencies: ["RelayCore"]),
        .executableTarget(name: "RelayCloudCheck", dependencies: ["RelayCore"]),
        .executableTarget(name: "RelayWorkflowCheck", dependencies: ["RelayCore"]),
        .executableTarget(name: "RelaySpeechCheck", dependencies: ["RelayCore"]),
        .executableTarget(name: "RelayNearbyCheck", dependencies: ["RelayCore"]),
        .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"])
    ],
    swiftLanguageModes: [.v5]
)
