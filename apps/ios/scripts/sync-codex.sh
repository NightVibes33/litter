#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/../.." && pwd)"
SUBMODULE_DIR="$REPO_DIR/shared/third_party/codex"
PATCH_FILES=(
    # Refreshed aggregate patch for NightVibes33 codex base with GPT-6-Astra backport.
    # Older per-feature patches are kept for history but no longer apply cleanly
    # after the Astra Codex bridge bump.
    "$REPO_DIR/patches/codex/mobile-bridge-codex-astra.patch"
)

patch_already_upstreamed() {
    return 1
}

SYNC_MODE="${1:---preserve-current}"
case "$SYNC_MODE" in
    --preserve-current|--recorded-gitlink)
        ;;
    *)
        echo "usage: $(basename "$0") [--preserve-current|--recorded-gitlink]" >&2
        exit 1
        ;;
esac

echo "==> Syncing codex submodule..."
if ! git -C "$SUBMODULE_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$REPO_DIR" submodule update --init --recursive shared/third_party/codex
elif [ "$SYNC_MODE" = "--recorded-gitlink" ]; then
    git -C "$REPO_DIR" submodule update --init --recursive shared/third_party/codex
else
    recorded_commit="$(git -C "$REPO_DIR" ls-files --stage shared/third_party/codex | awk 'NR == 1 { print $2 }')"
    current_commit="$(git -C "$SUBMODULE_DIR" rev-parse HEAD)"

    if [ -z "$recorded_commit" ]; then
        echo "error: could not resolve recorded submodule gitlink for shared/third_party/codex" >&2
        exit 1
    fi

    if [ "$current_commit" = "$recorded_commit" ]; then
        echo "==> codex submodule already at recorded gitlink ${current_commit:0:9}"
    else
        echo "==> Preserving current codex checkout ${current_commit:0:9} (recorded gitlink ${recorded_commit:0:9})"
    fi
fi

for PATCH_FILE in "${PATCH_FILES[@]}"; do
    PATCH_NAME="$(basename "$PATCH_FILE")"
    if [ ! -f "$PATCH_FILE" ]; then
        echo "error: missing patch file: $PATCH_FILE" >&2
        exit 1
    fi

    if git -C "$SUBMODULE_DIR" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
        echo "==> $PATCH_NAME already applied."
    elif git -C "$SUBMODULE_DIR" apply --check "$PATCH_FILE" >/dev/null 2>&1; then
        echo "==> Applying $PATCH_NAME to submodule..."
        git -C "$SUBMODULE_DIR" apply "$PATCH_FILE"
    elif patch_already_upstreamed "$PATCH_FILE"; then
        echo "==> $PATCH_NAME already present upstream; skipping patch apply."
    else
        # When multiple patches touch the same files, reverse-check may fail even
        # if the patch is applied.  Fall back to checking whether the added lines
        # are already present in the files the patch actually touches.
        patch_targets=()
        # Pick up both `diff --git a/... b/...` style and bare `--- a/...`
        # style hunks. Some hand-crafted patches omit the `diff --git` line
        # for their first file; without the `--- a/` fallback those files
        # get dropped from the content-check and cause false negatives.
        patch_target_list="$(mktemp)"
        { grep '^diff --git' "$PATCH_FILE" | sed 's|.*b/||'; \
          grep '^--- a/' "$PATCH_FILE" | sed 's|^--- a/||'; } | sort -u > "$patch_target_list"
        while IFS= read -r pf; do
            [ -f "$SUBMODULE_DIR/$pf" ] && patch_targets+=("$SUBMODULE_DIR/$pf")
        done < "$patch_target_list"
        rm -f "$patch_target_list"
        added_lines=$(grep -m 5 '^+[^+]' "$PATCH_FILE" | sed 's/^+//')
        all_present=true
        if [ "${#patch_targets[@]}" -eq 0 ]; then
            all_present=false
        else
            while IFS= read -r line; do
                trimmed="${line#"${line%%[![:space:]]*}"}"
                [ -z "$trimmed" ] && continue
                if ! grep -qF "$trimmed" "${patch_targets[@]}" 2>/dev/null; then
                    all_present=false
                    break
                fi
            done <<< "$added_lines"
        fi
        if [ "$all_present" = true ]; then
            echo "==> $PATCH_NAME already applied (content check)."
        else
            echo "error: $PATCH_NAME no longer applies cleanly to codex $(git -C "$SUBMODULE_DIR" rev-parse --short HEAD)" >&2
            echo "error: refresh $PATCH_FILE before rebuilding the bridge" >&2
            exit 1
        fi
    fi
done

verify_mobile_code_mode_bridge() {
    local code_mode_dir="$SUBMODULE_DIR/codex-rs/code-mode"
    local lib_rs="$code_mode_dir/src/lib.rs"
    local cargo_toml="$code_mode_dir/Cargo.toml"
    local service_mobile="$code_mode_dir/src/service_mobile.rs"
    local service_stub="$code_mode_dir/src/service_stub.rs"

    if [ ! -f "$service_mobile" ]; then
        echo "error: mobile code mode is missing service_mobile.rs" >&2
        exit 1
    fi

    if [ -f "$service_stub" ]; then
        echo "error: legacy mobile code-mode stub is present; refusing to build a tool-dead mobile Codex bridge" >&2
        exit 1
    fi

    if ! grep -qF 'mod service_mobile;' "$lib_rs"; then
        echo "error: code-mode lib.rs does not select service_mobile on mobile targets" >&2
        exit 1
    fi

    if ! grep -qF 'pub use service_mobile::*;' "$lib_rs"; then
        echo "error: mobile code-mode provider is not exported" >&2
        exit 1
    fi

    if ! grep -qF 'rquickjs = { workspace = true }' "$cargo_toml"; then
        echo "error: mobile code mode is missing its QuickJS runtime dependency" >&2
        exit 1
    fi

    if ! grep -qF 'use rquickjs::AsyncRuntime;' "$service_mobile"; then
        echo "error: service_mobile.rs is not the QuickJS-backed implementation" >&2
        exit 1
    fi

    if ! grep -qF 'globalThis.tools = Object.create(null);' "$service_mobile"; then
        echo "error: mobile code mode does not bootstrap the tools object" >&2
        exit 1
    fi

    if ! grep -qF 'globalThis.ALL_TOOLS = ' "$service_mobile"; then
        echo "error: mobile code mode does not expose ALL_TOOLS metadata" >&2
        exit 1
    fi

    if ! grep -qF 'impl CodeModeSessionProvider for InProcessCodeModeSessionProvider' "$service_mobile"; then
        echo "error: mobile code mode does not provide in-process sessions" >&2
        exit 1
    fi

    if ! grep -qF 'delegate.invoke_tool' "$service_mobile"; then
        echo "error: mobile code mode cannot delegate nested tool calls to the host" >&2
        exit 1
    fi

    if ! grep -qF 'impl CodeModeSessionProvider for ProcessOwnedCodeModeSessionProvider' "$service_mobile"; then
        echo "error: process-owned mobile code-mode provider is not routed to the in-process runtime" >&2
        exit 1
    fi

    if grep -Eqi 'code mode is unavailable on mobile|exec is unavailable on mobile targets|MOBILE_UNSUPPORTED_MESSAGE|const[[:space:]]+UNSUPPORTED' "$service_mobile"; then
        echo "error: unsupported mobile code-mode stub detected" >&2
        exit 1
    fi

    echo "==> Mobile code mode verified: QuickJS runtime + nested host tool delegation"
}

verify_mobile_code_mode_bridge

echo "==> codex submodule ready at $(git -C "$SUBMODULE_DIR" rev-parse --short HEAD)"
