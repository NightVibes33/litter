# LitterBuildKitNative

This is the private native-driver ABI that Litter expects when a sideload build
includes real Nyxian/CoreCompiler assets.

The public app loads `LitterBuildKitNative.framework` with `dlopen` and calls
`litter_buildkit_run_json`. The private framework should link against
`CoreCompiler.framework`, use the installed `CoreCompilerSupportLibs` and
`iPhoneOS26.4.sdk`, then return structured JSON diagnostics and artifact paths.

The framework is intentionally not built in the public CI lane because the full
asset bundle depends on user-owned Apple SDK files.
