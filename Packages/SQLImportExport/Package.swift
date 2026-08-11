// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLImportExport",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLImportExport", targets: ["SQLImportExport"]),
    ],
    dependencies: [
        .package(path: "../SQLDrivers"),
    ],
    targets: [
        .target(name: "SQLImportExport", dependencies: ["SQLDrivers"]),
        .testTarget(name: "SQLImportExportTests", dependencies: ["SQLImportExport"]),
    ]
)
