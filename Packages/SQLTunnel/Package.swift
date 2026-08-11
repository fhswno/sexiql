// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLTunnel",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLTunnel", targets: ["SQLTunnel"]),
    ],
    dependencies: [
        .package(path: "../SQLCore"),
    ],
    targets: [
        .target(name: "SQLTunnel", dependencies: ["SQLCore"]),
        .testTarget(name: "SQLTunnelTests", dependencies: ["SQLTunnel"]),
    ]
)
