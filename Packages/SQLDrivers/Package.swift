// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLDrivers",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLDrivers", targets: ["SQLDrivers"]),
    ],
    dependencies: [
        .package(path: "../SQLCore"),
        .package(path: "../SQLTunnel"),
    ],
    targets: [
        .target(name: "SQLDrivers", dependencies: ["SQLCore", "SQLTunnel"]),
        .testTarget(name: "SQLDriversTests", dependencies: ["SQLDrivers"]),
    ]
)
