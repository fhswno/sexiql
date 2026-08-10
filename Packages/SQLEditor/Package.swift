import PackageDescription

let package = Package(
    name: "SQLEditor",
    platforms: [.macOS(.version("26.0"))],
    products: [
        .library(name: "SQLEditor", targets: ["SQLEditor"]),
    ],
    targets: [
        .target(name: "SQLEditor"),
        .testTarget(name: "SQLEditorTests", dependencies: ["SQLEditor"]),
    ]
)
