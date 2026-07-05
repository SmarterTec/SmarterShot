// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmarterShot",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Pure, headless-testable logic (no AppKit): geometry, window picking,
        // sound-flag rules.
        .target(
            name: "SmarterShotCore",
            path: "Sources/SmarterShotCore"
        ),
        // The macOS app itself (AppKit UI).
        .executableTarget(
            name: "SmarterShot",
            dependencies: ["SmarterShotCore"],
            path: "Sources/SmarterShot"
        ),
        // Test harness. Built as a plain executable (not .testTarget) so it runs
        // with just the Command Line Tools — no full Xcode / XCTest needed.
        // Run with: swift run SmarterShotTests   (or ./test.sh)
        .executableTarget(
            name: "SmarterShotTests",
            dependencies: ["SmarterShotCore"],
            path: "Sources/SmarterShotTests"
        )
    ]
)
