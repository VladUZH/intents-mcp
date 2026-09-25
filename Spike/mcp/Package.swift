// swift-tools-version:6.1
// M0 spike: MCP handshake test, hand-written JSON-RPC vs the official Swift SDK 0.12.1.
import PackageDescription

let package = Package(
    name: "mcp-spike",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")],
    targets: [
        .executableTarget(name: "hand"),
        .executableTarget(name: "sdk", dependencies: [.product(name: "MCP", package: "swift-sdk")]),
    ]
)
