# Build Status

Last verified public build:

- Commit: `6afdf06bdb9367a962588f261496007943ca2350`
- Workflow: `Build Unsigned iOS IPA`
- Result: green before the private BuildKit asset-pack work began
- Artifact mode: unsigned SideStore/AltStore IPA for re-signing

Current BuildKit state:

- Public repo contains the app-side BuildKit bridge, fakefs command shims, fakefs doctor, native ABI wrapper source, and private asset manifest contract.
- Full on-device Swift/IPA building requires a private `LitterBuildKitAssets` bundle with CoreCompiler, Swift support libraries, `LitterBuildKitNative.framework`, a Nyxian runner or monolithic driver, and a user-owned `iPhoneOS26.4.sdk`.
- Apple SDK assets must not be committed to this public repository.
