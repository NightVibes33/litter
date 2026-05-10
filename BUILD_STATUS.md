# Build Status

Last verified public build:

- Commit: `9c78f95df9b9e10ec54c2038bfab7e35421d1730`
- Workflow: `Build Unsigned iOS IPA`
- Run: https://github.com/NightVibes33/litter/actions/runs/25630987712
- Result: green after the Nyxian BuildKit native wrapper/import work
- Artifact mode: unsigned SideStore/AltStore IPA for re-signing

Current BuildKit state:

- Public repo contains the app-side BuildKit bridge, fakefs command shims, fakefs doctor, native ABI wrapper source, and private asset manifest contract.
- Full on-device Swift/IPA building requires a private `LitterBuildKitAssets` bundle with CoreCompiler, Swift support libraries, `LitterBuildKitNative.framework`, a Nyxian runner or monolithic driver, and a user-owned `iPhoneOS26.4.sdk`.
- Apple SDK assets must not be committed to this public repository.

Latest implementation note:

- BuildKit now stages fakefs project files into app-visible `Documents/BuildKit/Jobs` before invoking native code.
- Private in-process driver mode source exists, but real local Swift/IPA execution still requires private CoreCompiler/support libs/iPhoneOS SDK validation on device.
- Current pending changes add real iOS Files folder/archive/image import paths, fakefs archive extraction, chat attachment path mentions, Hugging Face model detail sheets, GGUF sibling download cards, and persistent model install progress. These changes require the next unsigned IPA workflow run for compile verification.
