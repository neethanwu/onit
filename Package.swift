// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Onit",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "Onit",
            path: "Onit"
        ),
        .testTarget(
            name: "OnitTests",
            dependencies: ["Onit"],
            path: "Tests/OnitTests"
        ),
    ]
)
