// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLUI",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLUI", targets: ["SQLUI"]),
    ],
    targets: [
        .target(name: "SQLUI"),
    ]
)
