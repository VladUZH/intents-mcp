// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "intents-mcp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "intents-mcp", targets: ["intents-mcp"]),
    ],
    targets: [
        .target(name: "IntentsIndex"),
        .executableTarget(name: "intents-mcp", dependencies: ["IntentsIndex"], path: "Sources/CLI"),
        .testTarget(name: "IntentsIndexTests", dependencies: ["IntentsIndex"], resources: [.copy("Fixtures")]),
    ]
)
