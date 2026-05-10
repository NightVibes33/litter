# Litter iOS

`apps/ios` is the active native iOS app, not a placeholder. `project.yml` is the source of truth for regenerating `Litter.xcodeproj`.

## BuildKit

Litter imports relevant Nyxian source under `../../ThirdParty/Nyxian` and exposes a native BuildKit bridge to the iSH fakefs. Bots can call these commands from `/root` after app bootstrap:

- `litter-buildkit`
- `litter-swift-check`
- `litter-swift-test`
- `litter-ipa-build`
- `litter-ipa-package`
- `litter-build-status`
- `litter-build-cancel`

The command shims queue requests to the native app bridge and wait for status/log output by default. Use `--no-wait` for async jobs and `litter-build-status <id>` to inspect them later. Full local Swift/iOS compilation requires a packaged Nyxian/CoreCompiler toolchain bundle and iPhoneOS SDK assets; until those are installed, use the GitHub unsigned IPA workflow for full app builds.

## Regenerate Project

```bash
make xcgen
```

## Unsigned IPA

Use `.github/workflows/ios-unsigned-ipa.yml` for SideStore/AltStore-style unsigned IPA artifacts.
