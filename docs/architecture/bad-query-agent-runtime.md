# BadQuery Host Runtime Integration

Pinned upstream: `forcequitOS/bad_query@73ef6da1adabef0982fd00e36cb85f21b8f8194a`.

## Ownership

BadQuery is an AlleyCat native host-runtime capability. It is not owned by Codex, Nyxian, the iSH shell, or the `bad-query` compatibility command.

Unsigned AlleyCat builds compile the real upstream BadQuery C implementation into `LitterBuildKitNative.framework`. A sandbox extension consumed by `bad_query()` is consumed in the AlleyCat process. Native AlleyCat components may therefore share the host runtime's active BadQuery sessions instead of independently embedding or reimplementing the upstream primitive.

Codex is one optional consumer of AlleyCat host capabilities. It does not define BadQuery authorization semantics.

## Upstream ABI

The integration preserves the complete pinned upstream ABI:

```c
int64_t bad_query(char *path, bool create, char *group_identifier, bool is_group);
char *bad_query_list(char *path, int64_t max_inode);
void bad_query_release(int64_t handle);
```

The bridge must preserve `path`, `create`, `group_identifier`, `is_group`, and `max_inode` rather than replacing them with inferred defaults at the native API boundary.

Negative upstream return values remain observable:

- `-255`: path is not absolute
- `-254`: target does not exist when create mode is disabled
- `-1`: required private container/sandbox symbols are unavailable
- `-2`: query creation failed
- `-3`: query returned no result
- `-4`: sandbox extension was refused
- `-5`: traversal-string allocation failed

## Host sessions

Successful `bad_query()` handles are process-wide AlleyCat runtime resources. The runtime tracks every live handle, supports deterministic single-handle and release-all cleanup, rejects release requests for handles it does not own, and drops all remaining capability with process termination.

The compatibility CLI currently exposes:

```text
bad-query status
bad-query acquire --path /absolute/path [--create] [--group-id group.id] [--is-group]
bad-query list --path /absolute/path --max-inode N
bad-query release --handle N
bad-query release-all
```

These commands are a frontend to the native host runtime, not the ownership boundary.

## Policy

There is no BadQuery-specific Codex approval policy and no native per-command BadQuery alert. Codex and other consumers use AlleyCat's ordinary host/tool policy. Generic shell/tool safety behavior remains unchanged.

## Runtime detection

Do not infer availability solely from the OS version. The running host must surface whether the native BadQuery implementation is compiled and whether the requested upstream operation succeeds. `bad-query status` reports the compiled upstream revision and live-handle count.

LiveContainer hosting and BadQuery are separate capability sources. Access already provided by a LiveContainer-hosted environment must not be described as having been granted by BadQuery.

## Upstream documented scope

The pinned upstream README describes these roots depending on OS version:

- `/var/containers/Data/System` (iOS 27)
- `/var/containers/Shared/SystemGroup/*` (iOS 27)
- `/var/mobile/Containers/Data/Application/*`
- `/var/mobile/Containers/Data/InternalDaemon/*`
- `/var/mobile/Containers/Data/PluginKitPlugin/*`
- `/var/mobile/Containers/Shared/AppGroup/*` (iOS 26 with the upstream App Group requirement)
- `/var/mobile/Containers/Shared/AppGroup` (iOS 27)

These are upstream claims and are not treated as proof that a particular running device grants access.

## Verification

CI checks out submodules recursively, verifies the exact BadQuery revision, includes that revision in the native source fingerprint/cache key, compiles the upstream C source into the arm64 iOS native framework, and verifies that the resulting framework exports the BadQuery revision marker.

Regression checks should additionally fail if the old `LBNBadQueryRequireApproval` native gate or Codex-specific exact-command BadQuery approval instructions are reintroduced.
