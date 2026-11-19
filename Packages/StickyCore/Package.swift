// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StickyCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StickyCore", targets: ["StickyCore"]),
        .library(name: "StickyMCP", targets: ["StickyMCP"]),
        .executable(name: "stickydesk-mcp", targets: ["stickydesk-mcp"]),
    ],
    targets: [
        .target(name: "StickyCore"),
        .target(name: "StickyMCP", dependencies: ["StickyCore"]),
        .executableTarget(name: "stickydesk-mcp", dependencies: ["StickyMCP"]),
        .testTarget(name: "StickyCoreTests", dependencies: ["StickyCore"]),
        .testTarget(name: "StickyMCPTests", dependencies: ["StickyMCP", "StickyCore", "stickydesk-mcp"]),
    ],
    swiftLanguageModes: [.v6]
)
