// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FanPilot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FanPilot", targets: ["FanPilot"])
    ],
    targets: [
        .executableTarget(
            name: "FanPilot",
            path: "Sources/FanPilot"
        ),
        .testTarget(
            name: "FanPilotTests",
            dependencies: ["FanPilot"],
            path: "Tests/FanPilotTests"
        )
    ]
)
