// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "intents-mcp",
    // Shortcuts' `sign` and the App Intents metadata this reads need macOS 26 (tested on 27).
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "intents-mcp", targets: ["intents-mcp"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "IntentsIndex"),
        .target(name: "Store", dependencies: ["Core"]),
        .target(name: "ShortcutForge", dependencies: ["Core", "IntentsIndex"]),
        .target(name: "Runner", dependencies: ["Core", "ShortcutForge"]),
        .target(name: "MCPServer", dependencies: ["Core", "IntentsIndex", "Store", "ShortcutForge", "Runner"]),
        .executableTarget(
            name: "intents-mcp",
            dependencies: ["Core", "IntentsIndex", "Store", "ShortcutForge", "Runner", "MCPServer"],
            path: "Sources/CLI"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "IntentsIndexTests", dependencies: ["IntentsIndex"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ForgeTests", dependencies: ["Core", "ShortcutForge", "Runner", "Store", "IntentsIndex"]),
        .testTarget(name: "MCPServerTests", dependencies: ["Core", "MCPServer", "ShortcutForge", "Runner", "Store"],
                    resources: [.copy("Fixtures")]),
    ]
)
