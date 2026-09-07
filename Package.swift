// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatermarkTool",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WatermarkTool", targets: ["WatermarkTool"])
    ],
    targets: [
        .executableTarget(name: "WatermarkTool")
    ]
)