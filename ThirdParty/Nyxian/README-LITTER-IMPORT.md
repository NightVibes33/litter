# Nyxian Source Import for Litter BuildKit

This directory contains direct source imports from ProjectNyxian/Nyxian and ProjectNyxian/LLVM-On-iOS for Litter's on-device BuildKit work.

Nyxian is AGPL-3.0 licensed. Imported files keep their original headers where present. Litter treats this tree as third-party source and does not compile it directly into the app target until each subsystem is adapted and verified.

Integration intent:
- CoreCompiler: Swift/Clang diagnostics, object generation, and linker invocation.
- MobileDevelopmentKit: build phases, project/job modeling, and diagnostics.
- LindChain Project/LiveContainer: app bundle layout, plist/project helpers, unsigned packaging, and execution architecture references.
- LLVM-On-iOS: iOS-native Swift/LLVM toolchain build and packaging recipe.

The Litter app-side API lives in `apps/ios/Sources/Litter/Models/LitterBuildKit.swift`. Fakefs command shims queue requests for that native bridge instead of pretending Alpine can run Xcode.
