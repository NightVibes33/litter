#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/../.." && pwd)"
SUBMODULE_DIR="$REPO_DIR/shared/third_party/codex"
PATCH_FILES=(
    "$REPO_DIR/patches/codex/mobile-in-process-code-mode.patch"
    "$REPO_DIR/patches/codex/mobile-crypto-compat.patch"
    "$REPO_DIR/patches/codex/mobile-security-dependencies.patch"
    "$REPO_DIR/patches/codex/ios-exec-hook.patch"
    "$REPO_DIR/patches/codex/thread-read-permissions.patch"
    "$REPO_DIR/patches/codex/thread-list-fork-lineage.patch"
    "$REPO_DIR/patches/codex/mobile-shell-snapshot-timeout.patch"
    "$REPO_DIR/patches/codex/remote-app-server-websocket-cap.patch"
    "$REPO_DIR/patches/codex/absolute-path-cross-platform.patch"
    "$REPO_DIR/patches/codex/android-installation-id-lock.patch"
    "$REPO_DIR/patches/codex/android-armv7-file-mode.patch"
    "$REPO_DIR/patches/codex/dynamic-tool-call-arguments-delta.patch"
    "$REPO_DIR/patches/codex/approval-timestamps-serde-default.patch"
    "$REPO_DIR/patches/codex/realtime-webrtc-env-apikey.patch"
    # Realtime multi-server orchestrator (split from old client-controlled-handoff.patch).
    # Apply order: server-hint adds the realtime_v2_session_tools helper consumed by dynamic-tools.
    "$REPO_DIR/patches/codex/realtime-handoff-server-hint.patch"
    "$REPO_DIR/patches/codex/realtime-dynamic-tools.patch"
    "$REPO_DIR/patches/codex/realtime-client-controlled-handoff.patch"
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

# Root-owned source pin; the recorded gitlink remains the bootstrap checkout.
# Fetch the exact release commit, then apply this repository's mobile overlays.
CODEX_UPSTREAM_URL="https://github.com/openai/codex.git"
CODEX_UPSTREAM_REV="d27764b82f7118f674371e6d6e76271d9d606edb"
echo "==> Syncing pinned Codex 0.160.1..."
if [ ! -e "$SUBMODULE_DIR/.git" ]; then
    git -C "$REPO_DIR" submodule update --init shared/third_party/codex
fi
current_commit="$(git -C "$SUBMODULE_DIR" rev-parse HEAD)"
if [ "$current_commit" != "$CODEX_UPSTREAM_REV" ]; then
    if [ -n "$(git -C "$SUBMODULE_DIR" status --porcelain)" ]; then
        echo "error: preserve local Codex edits before switching to $CODEX_UPSTREAM_REV" >&2
        exit 1
    fi
    if ! git -C "$SUBMODULE_DIR" cat-file -e "$CODEX_UPSTREAM_REV^{commit}" 2>/dev/null; then
        git -C "$SUBMODULE_DIR" fetch --depth=1 "$CODEX_UPSTREAM_URL" "$CODEX_UPSTREAM_REV"
    fi
    git -C "$SUBMODULE_DIR" checkout --detach "$CODEX_UPSTREAM_REV"
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
        while IFS= read -r pf; do
            [ -f "$SUBMODULE_DIR/$pf" ] && patch_targets+=("$SUBMODULE_DIR/$pf")
        done < <({ grep '^diff --git' "$PATCH_FILE" | sed 's|.*b/||'; \
                    grep '^--- a/' "$PATCH_FILE" | sed 's|^--- a/||'; } | sort -u)
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

echo "==> codex submodule ready at $(git -C "$SUBMODULE_DIR" rev-parse --short HEAD)"
