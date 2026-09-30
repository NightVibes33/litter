# BadQuery Agent Runtime Integration

Pinned upstream: `forcequitOS/bad_query@73ef6da1adabef0982fd00e36cb85f21b8f8194a`.

## Purpose

Unsigned Alley Cãt builds compile the real upstream BadQuery C implementation into `LitterBuildKitNative.framework`. The iSH command shim named `bad-query` crosses into the native iOS process, so its path arguments are iOS host paths rather than iSH fakefs paths.

## Commands

```text
bad-query status
bad-query acquire --path /absolute/path [--create] [--group-id group.id] [--is-group]
bad-query list --path /absolute/path --max-inode N
bad-query release --handle N
bad-query release-all
```

`acquire` calls upstream `bad_query` directly and retains the returned sandbox-extension handle in the Alley Cãt process. `list` calls upstream `bad_query_list` directly. `release` and `release-all` call upstream `bad_query_release`.

## Approval behavior

The local Codex runtime instructions require the agent to request a user approval for the exact command before every `acquire`, `list`, `release`, or `release-all` operation. The instructions explicitly prohibit a persistent/blanket BadQuery prefix approval. `status` and `help` are capability-only checks.

## Upstream documented scope

The upstream README describes access to these roots depending on OS version:

- `/var/containers/Data/System` (iOS 27)
- `/var/containers/Shared/SystemGroup/*` (iOS 27)
- `/var/mobile/Containers/Data/Application/*`
- `/var/mobile/Containers/Data/InternalDaemon/*`
- `/var/mobile/Containers/Data/PluginKitPlugin/*`
- `/var/mobile/Containers/Shared/AppGroup/*` (iOS 26 with the upstream App Group requirement)
- `/var/mobile/Containers/Shared/AppGroup` (iOS 27)

The integration does not substitute a fake filesystem implementation or synthesize successful results. Negative return values from upstream are surfaced to the agent with diagnostic text.

## Verification

The private BuildKit workflow checks out submodules recursively, verifies the exact BadQuery commit, includes the BadQuery source revision in the native source fingerprint/cache key, compiles the C source into the arm64 iOS native framework, and verifies that the resulting framework exports the BadQuery revision marker and contains the exact pinned commit string.
