# Alley Cãt's pinned Nyxian toolchain

The full unsigned IPA builds its compiler dependencies from the nested
`ThirdParty/EmexDE/Source/LLVM-On-iOS` revision pinned by the Nyxian submodule.
Its upstream Makefile builds Swift, LLVM, and Clang together and packages their
installed and generated headers with the resulting iOS libraries. The complete
upstream Swift runtime toolchain is installed into Nyxian's `Shared` resources.
The safe App Store/TestFlight variant remains separate.

`.github/workflows/nyxian-toolchain.yml` runs the pinned Apple Silicon build
preset on `macos-26` with Xcode 26.3. The unsigned workflow depends on this job,
then downloads and verifies its artifact before archiving the embedded app.
Only the Objective-C/Swift framework embedding patches remain in this lane;
the old LLVM 19 header overlays and replacement Swift frontend are not applied.

The complete artifact cache is keyed by Nyxian revision, LLVM-On-iOS revision,
host architecture, Xcode version, and producer scripts. A provenance manifest
records the Swift tag, actual Swift and LLVM checkout revisions, and SHA-256
checksums for both artifact archives. The consumer rejects other source
revisions and changed archives. The first uncached build compiles the toolchain;
subsequent matching builds reuse the complete artifact pair.

A green IPA build verifies packaging, not on-device compiler execution.
After installing the full unsigned variant and preparing its iOS SDK resources,
use Alley Cãt's existing `litter-swift-selftest` command to exercise Swift, UIKit,
C, C++, Objective-C, Objective-C++, and IPA export. Keep its compiler diagnostics
and generated artifacts when checking ChatGPT's existing BuildKit command path.
On-device building and signing still require device validation.

The full unsigned archive also builds `LitterBuildKitNative.framework` against
the archived CoreCompiler, MobileDevelopmentKit, and OpenSSL frameworks. It
links the existing MDK framework instead of defining duplicate Objective-C
classes. Private asset packs cannot overwrite the matched compiler or its
support libraries. SDK payloads retain their separate import/private-lane path;
the safe TestFlight lane does not embed this compiler bridge.

BuildKit resolves Swift modules and Clang built-in headers from the bundled
`Shared/SwiftToolchain/usr` before consulting imported asset packs, keeping
runtime compiler resources aligned with the pinned native libraries.
