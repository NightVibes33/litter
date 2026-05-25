import XCTest
@testable import Litter

final class BuildKitTests: XCTestCase {
    func testBuildKitManifestDecodes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "bundleIdentifier": "com.sigkitten.litter.buildkit.private",
          "sdkVersion": "26.4",
          "swiftVersion": "6.x",
          "minimumIOS": "18.0",
          "toolchain": {
            "name": "Nyxian/CoreCompiler",
            "coreCompilerFramework": "Toolchains/Nyxian/CoreCompiler.framework",
            "nativeDriverFramework": "Toolchains/Nyxian/LitterBuildKitNative.framework",
            "nativeRunner": "Toolchains/Nyxian/bin/litter-buildkit-runner",
            "supportLibraries": "Toolchains/Nyxian/CoreCompilerSupportLibs",
            "sdkPath": "SDK/iPhoneOS26.4.sdk"
          },
          "capabilities": ["swift-check", "unsigned-ipa-build"],
          "requiredPaths": ["SDK/iPhoneOS26.4.sdk/SDKSettings.plist"],
          "sha256": {}
        }
        """
        let manifest = try JSONDecoder().decode(BuildKitAssetManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.sdkVersion, "26.4")
        XCTAssertEqual(manifest.toolchain.coreCompilerFramework, "Toolchains/Nyxian/CoreCompiler.framework")
        XCTAssertEqual(manifest.toolchain.nativeDriverFramework, "Toolchains/Nyxian/LitterBuildKitNative.framework")
        XCTAssertEqual(manifest.toolchain.nativeRunner, "Toolchains/Nyxian/bin/litter-buildkit-runner")
        XCTAssertEqual(manifest.toolchain.nativeDriverMode, "runner")
        XCTAssertTrue(manifest.capabilities.contains("unsigned-ipa-build"))
    }

    func testBuildKitShellWordsPreserveQuotedBotArguments() {
        let words = LitterBuildKit.shellWords(#"'hello world' 'a'\''b' '-D' 'DEBUG' '/root/My App/main.swift'"#)

        XCTAssertEqual(words, ["hello world", "a'b", "-D", "DEBUG", "/root/My App/main.swift"])
    }

    func testBuildProjectManifestDefaultsMissingSourcesToEmpty() throws {
        let json = """
        {
          "schemaVersion": 1,
          "name": "EntrypointOnly",
          "bundleIdentifier": "com.example.entrypoint",
          "deploymentTarget": "18.0",
          "product": "app",
          "entrypoint": "Sources/App.swift"
        }
        """

        let manifest = try JSONDecoder().decode(LitterBuildProjectManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.entrypoint, "Sources/App.swift")
        XCTAssertEqual(manifest.sources, [])

        let roundTrip = try JSONDecoder().decode(LitterBuildProjectManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertEqual(roundTrip.entrypoint, "Sources/App.swift")
        XCTAssertEqual(roundTrip.sources, [])
    }

    func testStagedProjectManifestRewritesFakefsPathsForNativeDriver() {
        let manifest = LitterBuildProjectManifest(
            schemaVersion: 1,
            name: "Demo",
            bundleIdentifier: "com.example.demo",
            deploymentTarget: "18.0",
            sdk: nil,
            product: "app",
            entrypoint: "/root/App/Sources/main.swift",
            sources: ["/root/App/Sources", "Relative.swift", "/root/Shared", "../Common"],
            resources: ["/root/App/Assets", "../Resources"],
            entitlements: "/root/App/App.entitlements",
            output: nil
        )

        let staged = LitterBuildKit.stagedProjectManifestForNativeDriver(manifest, fakefsProjectDir: "/root/App")

        XCTAssertEqual(staged.entrypoint, "Sources/main.swift")
        XCTAssertEqual(staged.sources, ["Sources", "Relative.swift", "_external/root/Shared", "_external/root/Common"])
        XCTAssertEqual(staged.resources, ["Assets", "_external/root/Resources"])
        XCTAssertEqual(staged.entitlements, "App.entitlements")
    }

    func testBuildKitAssetRefreshPrefersHigherSDKVersion() {
        let installed = buildKitManifest(sdkVersion: "26.2", createdAt: "2026-05-13T12:00:00Z")
        let available = buildKitManifest(sdkVersion: "26.4", createdAt: "2026-05-12T12:00:00Z")

        XCTAssertTrue(LitterBuildKit.assetManifest(available, shouldReplace: installed))
    }

    func testBuildKitAssetRefreshDoesNotDowngradeSDKVersion() {
        let installed = buildKitManifest(sdkVersion: "26.4", createdAt: "2026-05-12T12:00:00Z")
        let available = buildKitManifest(sdkVersion: "26.2", createdAt: "2026-05-13T12:00:00Z")

        XCTAssertFalse(LitterBuildKit.assetManifest(available, shouldReplace: installed))
    }

    func testBuildKitAssetRefreshUsesCreatedAtWithinSameSDKVersion() {
        let installed = buildKitManifest(sdkVersion: "26.4", createdAt: "2026-05-12T12:00:00Z")
        let available = buildKitManifest(sdkVersion: "26.4", createdAt: "2026-05-13T12:00:00Z")

        XCTAssertTrue(LitterBuildKit.assetManifest(available, shouldReplace: installed))
    }

    func testBuildKitDownloadDefaultsTargetPrivateRelease() {
        let config = BuildKitAssetDownloadConfig()

        XCTAssertEqual(config.owner, "NightVibes33")
        XCTAssertEqual(config.repo, "litter-buildkit-assets")
        XCTAssertEqual(config.tag, "buildkit-ios26.4-v1")
        XCTAssertEqual(config.assetName, "LitterBuildKitAssets.zip")
        XCTAssertNil(config.normalizedSHA256)
    }

    func testBuildKitSHA256SidecarParser() throws {
        let sha = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

        XCTAssertEqual(try BuildKitAssetDownloadStore.parseSHA256Sidecar("\(sha)  LitterBuildKitAssets.zip\n"), sha)
        XCTAssertThrowsError(try BuildKitAssetDownloadStore.parseSHA256Sidecar("not-a-sha"))
    }
}

private func buildKitManifest(sdkVersion: String, createdAt: String) -> BuildKitAssetManifest {
    BuildKitAssetManifest(
        schemaVersion: 1,
        bundleIdentifier: "com.sigkitten.litter.buildkit.private",
        createdAt: createdAt,
        sdkVersion: sdkVersion,
        swiftVersion: "6.x",
        minimumIOS: "18.0",
        toolchain: BuildKitAssetManifest.Toolchain(
            name: "Nyxian/CoreCompiler",
            coreCompilerFramework: "Toolchains/Nyxian/CoreCompiler.framework",
            nativeDriverFramework: "Toolchains/Nyxian/LitterBuildKitNative.framework",
            nativeRunner: "Toolchains/Nyxian/bin/litter-buildkit-runner",
            supportLibraries: "Toolchains/Nyxian/CoreCompilerSupportLibs",
            sdkPath: "SDK/iPhoneOS\(sdkVersion).sdk"
        ),
        capabilities: ["swift-check", "swift-build"],
        requiredPaths: [],
        sha256: nil
    )
}
