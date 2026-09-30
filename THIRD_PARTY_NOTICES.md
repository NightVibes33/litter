# Third-Party Notices

This repository is a fork of the original Litter project and also vendors or builds against several upstream projects. Each upstream keeps its own copyright and license terms. Exact vendored SideStore, Feather, minimuxer, Zsign-Package, LocalDevVPN, and Ghostty source refs are recorded in `ThirdParty/UPSTREAMS.md`.

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
  - Vendored source paths: `ThirdParty/SideStore/Source`, `ThirdParty/SideStore/MinimuxerWrapper.swift`, and `ThirdParty/SideStore/minimuxer`
  - Role in Litter: SideStore-compatible sideloading expectations, public Anisette server list conventions, LocalDevVPN install/refresh model, update-source compatibility target, and the minimuxer transport API Litter is adapting for KittyStore install/refresh.
  - License: AGPL-3.0 for SideStore and minimuxer source.
- AltStore / Riley Testut and contributors
  - Upstream: https://github.com/altstoreio/AltStore and https://github.com/rileytestut/AltStore
  - Website/docs: https://altstore.io
  - Role in Litter: original AltStore sideloading, signing, refresh, and app-source model that SideStore extends and that Litter's source metadata targets.
  - License: AGPL-3.0 for AltStore source, with upstream's additional permission language for Riley Testut's original code in its README.
- Feather / khcrysalis and contributors
  - Upstream: https://github.com/khcrysalis/Feather
  - Vendored source path: `ThirdParty/Feather/Source`
  - Role in Litter: certificate-paired IPA signing workflow, signer screen structure, advanced modify/properties flow, and on-device signing expectations used by KittyStore.
  - License: GPL-3.0 for Feather source.
- Zsign / zhlynn and contributors
  - Upstream: https://github.com/zhlynn/zsign
  - Vendored source path: `ThirdParty/Feather/Zsign-Package`
  - Role in Litter: native IPA signing engine used by KittyStore's Feather-style BuildKit signer.
  - License: MIT, see `ThirdParty/Feather/Zsign-Package/LICENSE`.
- LocalDevVPN / Coxson Engineering LLC / jkcoxson
  - Upstream: https://github.com/jkcoxson/LocalDevVPN
  - App Store listing: https://apps.apple.com/us/app/localdevvpn/id6755608044
  - Vendored source paths: `ThirdParty/SideStore/LocalDevVPN-Source` and `ThirdParty/SideStore/LocalDevVPN-TunnelProv`
  - Role in Litter: LocalDevVPN-style tunnel detection and tunnel-provider source used for the KittyStore install/refresh transport work.
- minimuxer / jkcoxson and SideStore contributors
  - Upstreams: https://github.com/jkcoxson/minimuxer and https://github.com/SideStore/minimuxer
  - Vendored source path: `ThirdParty/SideStore/minimuxer`
  - Role in Litter: SideStore device-communication layer being adapted for KittyStore install/refresh transport.
  - License: AGPL-3.0, see `ThirdParty/SideStore/minimuxer/LICENSE`.
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

## Ghostty

Litter vendors Ghostty as a pinned submodule for the mobile terminal renderer work.

- Upstream: https://github.com/ghostty-org/ghostty
- Vendored path: `shared/third_party/ghostty`
- Pinned commit: `a968e120dd084bd886239d1cac938f0177f019d9`
- Local patch path: `patches/ghostty/litter-mobile-embed.patch`
- License: see `shared/third_party/ghostty/LICENSE` when the submodule is checked out.

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

## Updated KittyStore Signing Dependencies

- SideSign / SideStore contributors
  - Upstream: https://github.com/SideStore/SideSign
  - Vendored source: `ThirdParty/SideStore/SideSign`, revision `6b68651697f99791ef85404b7aea1891a26a285d`.
  - Role: KittyStore signing engine, called through a public adapter owned by the SideStore framework.
  - Upstream license declaration: GPL-3.0, retained in `ThirdParty/SideStore/SideSign/README.md`.
- AnisetteKit / mahee96 and contributors
  - Upstream: https://github.com/mahee96/AnisetteKit
  - Vendored source: `ThirdParty/SideStore/AnisetteKit`, revision `db8b41022697b6c19be8a5f01a1ce834145a2a26`.
  - License: AGPL-3.0, retained in `ThirdParty/SideStore/AnisetteKit/LICENSE`.
- Unicorn Engine and contributors
  - Pinned source fork: https://github.com/mahee96/unicorn at `a53ddc9ac6d65b24936d4a37917333fcd816cfd0`.
  - Source: `ThirdParty/SideStore/Unicorn`; rebuilt for iOS 18 and macOS 12.
  - Upstream license texts are retained in `COPYING`, `COPYING.LGPL2`, `COPYING_GLIB`, and nested component notices.
- EMProxy / SideStore contributors
  - Source build reference: https://github.com/SideStore/em_proxy at `6e117e140ca7cff4ff106bdefa18147552a0e592`.
  - License: AGPL-3.0, retained by the pinned source build in its upstream `LICENSE`.
- IDevice / Jackson Coxson and contributors
  - Source build reference: https://github.com/SideStore/idevice at `3e55c8486b2057e40c1f74aaaa1155c82341cf76`.
  - License: MIT, retained by the pinned source build in its upstream `LICENSE.txt`.

Exact signing dependencies and local compatibility overlays are recorded in `ThirdParty/SideStore/SideSign/LITTER_IMPORT.json`, `ThirdParty/SideStore/AnisetteKit/LITTER_IMPORT.json`, and `ThirdParty/UPSTREAMS.md`. The next minimuxer graph is audited separately in `docs/architecture/minimuxer-next-dependency-audit.json` and has not replaced the current transport.

## Released Nyxian Compiler

The full device build stages only CoreCompiler and its 13 matching compiler support libraries from Nyxian release `0.11.4`, source revision `0c61cfb57ee3d85d96a7102132db4268bcaa1db3`. The original compiler implementation and library bytes are preserved. Exact archive identifiers, checksum, source dependency pins, and license sources are recorded in `docs/architecture/nyxian-released-compiler.json`.

CoreCompiler's public source headers retain their MIT notices. Swift and LLVM license texts, including their LLVM exceptions, and cmark's component notices are retained in `docs/licenses/upstream-compiler` and copied into the staged compiler framework. The pinned source references for those notices are Swift `064859e41d68596f486c5d724401cb370f260409`, LLVM project `82cdc19fa54d566969527b56f587ea8ea30bef51`, and swift-cmark `924936d0427cb25a61169739a7660230bffa6ea6`.

## BadQuery

Alley Cãt's unsigned/private BuildKit runtime can compile the real forcequitOS BadQuery sandbox-escape PoC into `LitterBuildKitNative.framework`.

- Upstream: https://github.com/forcequitOS/bad_query
- Vendored path: `ThirdParty/bad_query` (git submodule)
- Pinned commit: `73ef6da1adabef0982fd00e36cb85f21b8f8194a`
- Runtime API retained from upstream: `bad_query`, `bad_query_list`, and `bad_query_release`.
- Upstream describes the PoC as targeting iOS 26.0-26.6.1 and iOS 27.0 beta 4, with documented access to selected system/app container roots.
- The pinned upstream snapshot does not contain a LICENSE file. Review upstream redistribution terms before distributing builds that contain this source.
