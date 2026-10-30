// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Onit",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        // Updates: signed, delta-free DMG updates from GitHub releases.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Onit",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Onit",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "OnitTests",
            dependencies: ["Onit"],
            path: "Tests/OnitTests"
        ),
    ]
)
