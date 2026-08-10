// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLExplainer",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLExplainer", targets: ["SQLExplainer"]),
    ],
    targets: [
        .target(name: "SQLExplainer"),
        .testTarget(name: "SQLExplainerTests", dependencies: ["SQLExplainer"]),
    ]
)
