#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Private Litter BuildKit ABI expected by the app.
/// Input: UTF-8 JSON request with command, args, cwd, buildDir, buildKitRoot,
/// toolchainRoot, and sdkRoot.
/// Output: allocated UTF-8 JSON response with exitCode, status, and log.
const char *litter_buildkit_run_json(const char *request_json);

/// Returns the exact forcequitOS/bad_query source revision compiled into the
/// native runtime, or NULL when BadQuery support was not compiled.
const char *litter_bad_query_upstream_commit(void);

/// Direct AlleyCat host-runtime BadQuery ABI. These functions are usable by
/// native AlleyCat components without routing through the iSH compatibility CLI.
/// They preserve the pinned upstream bad_query arguments and process-wide handle
/// lifetime. Negative acquire results are the upstream BadQuery error codes.
int64_t litter_bad_query_acquire(const char *path, bool create, const char *group_identifier, bool is_group);
char *litter_bad_query_list_copy(const char *path, int64_t max_inode);
bool litter_bad_query_release_handle(int64_t handle);
uint64_t litter_bad_query_release_all(void);
uint64_t litter_bad_query_active_handle_count(void);

/// Optional. Called by Litter after copying the response string.
void litter_buildkit_free_string(const char *response_json);

#ifdef __cplusplus
}
#endif
