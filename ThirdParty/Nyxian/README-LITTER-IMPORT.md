# Nyxian Source Import for Litter BuildKit

This directory contains direct source imports from ProjectNyxian/Nyxian and ProjectNyxian/LLVM-On-iOS for Litter's on-device BuildKit work.

Nyxian is AGPL-3.0 licensed. Imported files keep their original headers where present. Litter treats this tree as third-party source and does not compile it directly into the app target until each subsystem is adapted and verified.

Integration intent:
- CoreCompiler: Swift/Clang diagnostics, object generation, and linker invocation.
- MobileDevelopmentKit: build phases, project/job modeling, and diagnostics.
- LindChain Project/LiveContainer: app bundle layout, plist/project helpers, unsigned packaging, and execution architecture references.
- LLVM-On-iOS: iOS-native Swift/LLVM toolchain build and packaging recipe.

The Litter app-side API lives in `apps/ios/Sources/Litter/Models/LitterBuildKit.swift`. Fakefs command shims queue requests for that native bridge instead of pretending Alpine can run Xcode.

Private driver status:
- Litter now includes `LitterBuildKitNative.mm`, a buildable ABI wrapper that delegates requests to a packaged Nyxian runner.
- The runner is private/user-supplied because it links CoreCompiler support libraries and user-owned iPhoneOS SDK assets.
- Package the runner at `Toolchains/Nyxian/bin/litter-buildkit-runner` inside `LitterBuildKitAssets` or provide a monolithic driver framework with the same `litter_buildkit_run_json` ABI.
