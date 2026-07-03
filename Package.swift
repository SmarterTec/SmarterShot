// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmarterShot",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SmarterShot",
            path: "Sources/SmarterShot"
        )
    ]
)
