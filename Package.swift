// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mijia-mac",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MijiaCore", targets: ["MijiaCore"]),
    ],
    targets: [
        .target(name: "MijiaCore"),
        .executableTarget(name: "mijia-probe", dependencies: ["MijiaCore"]),
        .testTarget(name: "MijiaCoreTests", dependencies: ["MijiaCore"]),
    ]
)
