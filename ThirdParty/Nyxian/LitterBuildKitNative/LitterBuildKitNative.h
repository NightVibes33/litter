#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Private Litter BuildKit ABI expected by the app.
/// Input: UTF-8 JSON request with command, args, cwd, buildDir, buildKitRoot,
/// toolchainRoot, and sdkRoot.
/// Output: allocated UTF-8 JSON response with exitCode, status, and log.
const char *litter_buildkit_run_json(const char *request_json);

/// Optional. Called by Litter after copying the response string.
void litter_buildkit_free_string(const char *response_json);

#ifdef __cplusplus
}
#endif
