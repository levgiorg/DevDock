// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DevDock",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/laurieesc/flicker-dot", exact: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "DevDock",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "FlickerDot", package: "flicker-dot"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "DevDockTests", dependencies: ["DevDock", .product(name: "Testing", package: "swift-testing")])
    ],
    swiftLanguageModes: [.v5]
)
