// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Litter",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "Litter", targets: ["Litter"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20")
    ],
    targets: [
        .binaryTarget(
            name: "codex_bridge",
            path: "apps/ios/Frameworks/codex_bridge.xcframework"
        ),
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b9070/llama-b9070-xcframework.zip",
            checksum: "7c9352dcab083c40cadaebfbb67a44c6500ca254d476ba83fb419d770425681f"
        ),
        .target(
            name: "Litter",
            dependencies: ["codex_bridge", "llama", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            path: "apps/ios/Sources/Litter",
            publicHeadersPath: "Bridge"
        )
    ]
)
