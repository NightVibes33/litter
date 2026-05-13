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

    func testLocalModelBuildKitToolParsingAndRisk() {
        let calls = LocalModelToolLoop.parseToolCalls(from: "{\"tool\":\"ipa_build\",\"arguments\":{\"project_path\":\"/root/App/LitterBuild.json\"}}")

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "ipa_build")
        XCTAssertEqual(calls.first?.arguments["project_path"], "/root/App/LitterBuild.json")
        XCTAssertEqual(calls.first.map(LocalModelToolLoop.risk(for:)), .build)
    }

    func testLocalModelSwiftSelftestToolParsingAndRisk() {
        let calls = LocalModelToolLoop.parseToolCalls(from: "{\"tool\":\"swift_selftest\",\"arguments\":{}}")

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "swift_selftest")
        XCTAssertEqual(calls.first.map(LocalModelToolLoop.risk(for:)), .build)
    }

    func testLocalModelNyxianStatusToolIsSafeRead() {
        let calls = LocalModelToolLoop.parseToolCalls(from: "{\"tool\":\"nyxian_status\",\"arguments\":{}}")

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "nyxian_status")
        XCTAssertEqual(calls.first.map(LocalModelToolLoop.risk(for:)), .safeRead)
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
