// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Isola",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Isola",
            path: "Sources/Isola"
        )
    ]
)
