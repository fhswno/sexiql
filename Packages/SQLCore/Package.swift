// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLCore",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLCore", targets: ["SQLCore"]),
    ],
    targets: [
        .target(name: "SQLCore"),
        .testTarget(name: "SQLCoreTests", dependencies: ["SQLCore"]),
    ]
)
