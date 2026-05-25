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
        .target(
            name: "Litter",
            dependencies: ["codex_bridge", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            path: "apps/ios/Sources/Litter",
            publicHeadersPath: "Bridge"
        )
    ]
)
