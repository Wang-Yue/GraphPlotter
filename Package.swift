// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GraphPlotter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GraphPlotter",
            path: "GraphPlotter"
        )
    ]
)
