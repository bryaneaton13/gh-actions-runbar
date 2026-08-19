// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RunBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "RunBar", targets: ["RunBar"]),
        .library(name: "RunBarCore", targets: ["RunBarCore"]),
    ],
    targets: [
        .target(
            name: "RunBarCore",
            path: "Sources/RunBarCore"
        ),
        .executableTarget(
            name: "RunBar",
            dependencies: ["RunBarCore"],
            path: "Sources/RunBar"
        ),
        .executableTarget(
            name: "RunBarCoreChecks",
            dependencies: ["RunBarCore"],
            path: "Sources/RunBarCoreChecks"
        ),
    ]
)
