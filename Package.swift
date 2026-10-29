// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevSweep",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SweepKit"),
        .executableTarget(
            name: "DevSweep",
            dependencies: ["SweepKit"]
        ),
        .testTarget(
            name: "SweepKitTests",
            dependencies: ["SweepKit"]
        ),
    ]
)
