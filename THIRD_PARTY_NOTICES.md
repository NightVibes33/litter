# Third-Party Notices

This repository is a fork of the original Litter project and also vendors or builds against several upstream projects. Each upstream keeps its own copyright and license terms.

## Original Litter Upstream

- Upstream: https://github.com/dnakov/litter
- Original creator/upstream maintainer: Daniel Nakov / dnakov
- Current public fork: https://github.com/NightVibes33/litter
- License for Litter code: GPLv3 with the additional GPLv3 section 7 store-distribution permission in `LICENSE`

Accepted upstream contributors are listed in `AUTHORS.md`.

## Sideloading Ecosystem References

Litter builds unsigned IPA artifacts, emits AltStore/SideStore-compatible source metadata, and documents SideStore-style Apple ID, Anisette, certificate, LocalDevVPN, install, refresh, and Feather-style certificate signing flows. The projects below are credited because their public work defines that ecosystem. Unless a vendored path is named elsewhere in this file, this repo is referencing their behavior, formats, UI patterns, or public services rather than claiming ownership of their code.

- SideStore Team and contributors
  - Upstream: https://github.com/SideStore/SideStore
  - Website/docs: https://sidestore.io and https://docs.sidestore.io
  - Role in Litter: SideStore-compatible sideloading expectations, public Anisette server list conventions, LocalDevVPN install/refresh model, and update-source compatibility target.
  - License: AGPL-3.0 for SideStore source.
- AltStore / Riley Testut and contributors
  - Upstream: https://github.com/altstoreio/AltStore and https://github.com/rileytestut/AltStore
  - Website/docs: https://altstore.io
  - Role in Litter: original AltStore sideloading, signing, refresh, and app-source model that SideStore extends and that Litter's source metadata targets.
  - License: AGPL-3.0 for AltStore source, with upstream's additional permission language for Riley Testut's original code in its README.
- Feather / khcrysalis and contributors
  - Upstream: https://github.com/khcrysalis/Feather
  - Role in Litter: referenced certificate-paired IPA signing workflow, signer screen structure, advanced modify/properties flow, and on-device signing expectations.
  - License: GPL-3.0 for Feather source.
- Zsign / zhlynn and contributors
  - Upstream: https://github.com/zhlynn/zsign
  - Role in Litter: referenced signing engine used by Feather-style on-device IPA signing research.
- LocalDevVPN / Coxson Engineering LLC / jkcoxson
  - Upstream: https://github.com/jkcoxson/LocalDevVPN
  - App Store listing: https://apps.apple.com/us/app/localdevvpn/id6755608044
  - Role in Litter: LocalDevVPN-style tunnel detection for future on-device install/refresh readiness.
- minimuxer / jkcoxson and SideStore contributors
  - Upstreams: https://github.com/jkcoxson/minimuxer and https://github.com/SideStore/minimuxer
  - Role in Litter: referenced SideStore device-communication layer for install/refresh transport planning.
- em_proxy / jkcoxson and SideStore contributors
  - Upstreams: https://github.com/jkcoxson/em_proxy and https://github.com/SideStore/em_proxy
  - Role in Litter: referenced SideStore proxy/tunnel infrastructure for iOS loopback limitations.
  - License: AGPL-3.0 for the SideStore fork.
- Jitterbug / osy and contributors
  - Upstream: https://github.com/osy/Jitterbug
  - Role in Litter: referenced loopback/debugging approach used in SideStore's LocalDevVPN explanation.
  - License: Apache-2.0.

## OpenAI Codex

Litter vendors OpenAI Codex source for the shared mobile client and local Codex runtime integration.

- Vendored path: `shared/third_party/codex`
- License: Apache License 2.0, see `shared/third_party/codex/LICENSE`
- Notice: see `shared/third_party/codex/NOTICE`

## Nyxian / emexDE

Litter vendors source from ProjectNyxian/Nyxian as the foundation for its on-device iOS toolchain and BuildKit work.

- Upstream: https://github.com/ProjectNyxian/Nyxian
- Vendored path: `ThirdParty/Nyxian`
- Pinned commit: `d955607acf4e8112c28d1db01837fc3e11631de3`
- License: GNU Affero General Public License v3.0 or later, see `ThirdParty/Nyxian/LICENSE`

The vendored source intentionally excludes generated/private build outputs such as Apple SDK files, compiled frameworks, compiler ZIP payloads, app artwork/image payloads, IPA files, certificates, provisioning profiles, and signing identities. Those artifacts are produced or supplied through the private BuildKit asset pipeline.

## LLVM-On-iOS

Nyxian references ProjectNyxian/LLVM-On-iOS for compiler support libraries used by CoreCompiler. Litter's private BuildKit asset workflow fetches this dependency during asset packaging instead of committing generated compiler assets into the public app repo.

- Upstream: https://github.com/ProjectNyxian/LLVM-On-iOS
- Runtime/build artifact path: `ThirdParty/Nyxian/LLVM-On-iOS` during private asset builds
- License: see `ThirdParty/Nyxian/LLVM-On-iOS/LICENSE` when the dependency is present

## iSH Runtime Backend

The iOS Rust bridge depends on Daniel Nakov's iSH embedding backend for local fakefs command execution.

- Upstream: https://github.com/dnakov/litter-ish
- Referenced by: `shared/rust-bridge/codex-mobile-client/Cargo.toml`

## Alleycat Bridge Crates

The Rust mobile bridge references Alleycat bridge crates for connected computer and external agent bridge behavior.

- Upstream: https://github.com/dnakov/alleycat
- Referenced by: `shared/rust-bridge/Cargo.toml`

## ZIPFoundation

The Swift package manifest depends on ZIPFoundation for ZIP archive handling.

- Upstream: https://github.com/weichsel/ZIPFoundation
- Referenced by: `Package.swift`

## Rust, SwiftPM, and System Dependencies

The repository uses Rust crates, Swift packages, Xcode/Apple SDK files, and other package-manager dependencies. Those dependencies retain their upstream licenses. Release/legal audits should review `Cargo.lock`, `Package.resolved`, vendored license files, and binary artifact notices for the exact dependency set used by that release.

## Apple SDK Assets

Apple iPhoneOS SDK files are not committed to this repository. They are resolved from Xcode on the private macOS build runner and packaged only into the private `LitterBuildKitAssets.zip` used by sideload builds.
