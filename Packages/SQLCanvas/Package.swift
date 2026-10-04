// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLCanvas",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLCanvas", targets: ["SQLCanvas"]),
    ],
    targets: [
        .target(name: "SQLCanvas"),
        .testTarget(name: "SQLCanvasTests", dependencies: ["SQLCanvas"]),
    ]
)
