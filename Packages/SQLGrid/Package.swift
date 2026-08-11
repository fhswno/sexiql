// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLGrid",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLGrid", targets: ["SQLGrid"]),
    ],
    dependencies: [
        .package(path: "../SQLDrivers"),
    ],
    targets: [
        .target(name: "SQLGrid", dependencies: ["SQLDrivers"]),
        .testTarget(name: "SQLGridTests", dependencies: ["SQLGrid"]),
    ]
)
