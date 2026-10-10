// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftDependencySecurityCheck",
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor", exact: "4.122.2"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.101.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", exact: "1.45.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    ],
    targets: [.executableTarget(name: "DependencyCheck", dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP2", package: "swift-nio-http2"),
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
        .product(name: "Crypto", package: "swift-crypto"),
    ])]
)
