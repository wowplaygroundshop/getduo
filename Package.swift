// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GetDuo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GetDuo",
            path: "Sources/GetDuo",
            exclude: ["Shader.metal"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
