// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Minimuxer",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "Minimuxer",
            targets: ["Minimuxer"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/weichsel/ZIPFoundation.git",
            .upToNextMajor(from: "0.9.0")
        )
    ],
    targets: [
        .binaryTarget(
            name: "RustBridgeLib",
            path: "RustBridge/lib/RustBridge.xcframework"
        ),
        .target(
            name: "RustBridge",
            dependencies: ["RustBridgeLib"],
            path: "RustBridge",
            exclude: [
                "Cargo.toml",
                "Cargo.lock",
                "src",
                "Makefile",
                "lib",
            ],
            sources: ["MinimuxerBridge.swift", "MinimuxerBridgeIdevice.swift"]
        ),
        // MARK: Main SPM target
        .target(
            name: "Minimuxer",
            dependencies: [
                "RustBridge",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources"
        )
    ]
)
