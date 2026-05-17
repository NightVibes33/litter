# Third-Party Notices

## Nyxian / emexDE

Litter vendors source from ProjectNyxian/Nyxian as the foundation for its on-device iOS toolchain and BuildKit work.

- Upstream: https://github.com/ProjectNyxian/Nyxian
- Vendored path: `ThirdParty/Nyxian`
- Pinned commit: `d955607acf4e8112c28d1db01837fc3e11631de3`
- License: GNU Affero General Public License v3.0 or later

The vendored source intentionally excludes generated/private build outputs such as Apple SDK files, compiled frameworks, compiler ZIP payloads, app artwork/image payloads, IPA files, certificates, provisioning profiles, and signing identities. Those artifacts are produced or supplied through the private BuildKit asset pipeline.

## LLVM-On-iOS

Nyxian references ProjectNyxian/LLVM-On-iOS for compiler support libraries used by CoreCompiler. Litter's private BuildKit asset workflow fetches this dependency during asset packaging instead of committing generated compiler assets into the public app repo.

- Upstream: https://github.com/ProjectNyxian/LLVM-On-iOS
- Runtime/build artifact path: `ThirdParty/Nyxian/LLVM-On-iOS` during private asset builds

## Apple SDK Assets

Apple iPhoneOS SDK files are not committed to this repository. They are resolved from Xcode on the private macOS build runner and packaged only into the private `LitterBuildKitAssets.zip` used by sideload builds.
