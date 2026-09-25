// swift-tools-version:6.1
import PackageDescription

// The CLI embeds Support/Info.plist so EventKit read-back can show its usage strings.
let infoPlist = Context.packageDirectory + "/Support/Info.plist"

let package = Package(
    name: "intents-mcp",
    platforms: [.macOS(.v14)],
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
            path: "Sources/CLI",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                                           "-Xlinker", infoPlist])]),
        .testTarget(name: "IntentsIndexTests", dependencies: ["IntentsIndex"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ForgeTests", dependencies: ["Core", "ShortcutForge", "Runner", "Store", "IntentsIndex"]),
        .testTarget(name: "MCPServerTests", dependencies: ["Core", "MCPServer", "ShortcutForge"], resources: [.copy("Fixtures")]),
    ]
)
