# LitterBuildKitNative

`LitterBuildKitNative.framework` is the private native-driver ABI that the
Litter app loads with `dlopen` when an on-device BuildKit asset pack is
installed.

The public source now includes a buildable wrapper implementation:

- `LitterBuildKitNative.h` exposes `litter_buildkit_run_json` and
  `litter_buildkit_free_string`.
- `LitterBuildKitNative.mm` validates the JSON request, writes
  `<buildDir>/request.json`, locates a Nyxian runner, executes it, captures
  stdout/stderr, and returns JSON status/log output to Swift.
- `tools/scripts/build-litter-buildkit-native.sh` builds the framework on
  macOS/Xcode for private sideload asset packs.

The wrapper intentionally does not embed Apple SDK files or Swift compiler
payloads. The private asset pack must supply `CoreCompiler.framework`,
`CoreCompilerSupportLibs`, a user-owned `iPhoneOS26.4.sdk`, and either a
monolithic native driver or an executable runner at
`Toolchains/Nyxian/bin/litter-buildkit-runner`.

Expected runner invocation:

```sh
litter-buildkit-runner <command> \
  --request <buildDir>/request.json \
  --cwd <fakefs-cwd> \
  --args <original-args> \
  --build-dir <buildDir> \
  --buildkit-root <Documents/BuildKit> \
  --toolchain-root <Documents/BuildKit/Toolchains/Nyxian> \
  --sdk-root <Documents/BuildKit/SDK/iPhoneOS26.4.sdk>
```

The runner should exit with the compiler/build status code and write human
readable diagnostics to stdout/stderr. Litter stores that output under
`/root/builds/<job-id>/log.txt`.
