// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoBook",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DuoBook",
            path: "Sources/DuoBook",
            exclude: ["Shader.metal"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
