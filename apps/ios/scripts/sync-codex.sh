#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/../.." && pwd)"
SUBMODULE_DIR="$REPO_DIR/shared/third_party/codex"
PATCH_FILES=(
    "$REPO_DIR/patches/codex/mobile-crypto-compat.patch"
    "$REPO_DIR/patches/codex/ios-exec-hook.patch"
    "$REPO_DIR/patches/codex/thread-read-permissions.patch"
    "$REPO_DIR/patches/codex/thread-list-fork-lineage.patch"
    "$REPO_DIR/patches/codex/mobile-shell-snapshot-timeout.patch"
    "$REPO_DIR/patches/codex/remote-app-server-websocket-cap.patch"
    "$REPO_DIR/patches/codex/absolute-path-cross-platform.patch"
    "$REPO_DIR/patches/codex/android-installation-id-lock.patch"
    "$REPO_DIR/patches/codex/dynamic-tool-call-arguments-delta.patch"
    "$REPO_DIR/patches/codex/approval-timestamps-serde-default.patch"
    "$REPO_DIR/patches/codex/realtime-webrtc-env-apikey.patch"
    "$REPO_DIR/patches/codex/realtime-handoff-server-hint.patch"
    "$REPO_DIR/patches/codex/realtime-dynamic-tools.patch"
    "$REPO_DIR/patches/codex/realtime-client-controlled-handoff.patch"
)

SYNC_MODE="${1:---preserve-current}"
case "$SYNC_MODE" in
    --preserve-current|--recorded-gitlink) ;;
    *)
        echo "usage: $(basename "$0") [--preserve-current|--recorded-gitlink]" >&2
        exit 1
        ;;
esac

echo "==> Syncing codex submodule..."
if [ ! -e "$SUBMODULE_DIR/.git" ] || ! git -C "$SUBMODULE_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$REPO_DIR" submodule update --init --recursive shared/third_party/codex
elif [ "$SYNC_MODE" = "--recorded-gitlink" ]; then
    git -C "$REPO_DIR" submodule update --init --recursive shared/third_party/codex
else
    recorded_commit="$(git -C "$REPO_DIR" ls-files --stage shared/third_party/codex | awk 'NR == 1 { print $2 }')"
    current_commit="$(git -C "$SUBMODULE_DIR" rev-parse HEAD)"
    if [ -z "$recorded_commit" ]; then
        echo "error: could not resolve recorded codex gitlink" >&2
        exit 1
    fi
    if [ "$current_commit" = "$recorded_commit" ]; then
        echo "==> codex already at recorded gitlink ${current_commit:0:9}"
    else
        echo "==> Preserving current codex checkout ${current_commit:0:9} (recorded ${recorded_commit:0:9})"
    fi
fi

recorded_commit="$(git -C "$REPO_DIR" ls-files --stage shared/third_party/codex | awk 'NR == 1 { print $2 }')"
current_commit="$(git -C "$SUBMODULE_DIR" rev-parse HEAD)"
if [ "$recorded_commit" != "be2951ea34f0d295ed0becf97079f92fa5f6950e" ]; then
    echo "error: Litter runtime lock expects Codex be2951ea34f0d295ed0becf97079f92fa5f6950e, gitlink is $recorded_commit" >&2
    exit 1
fi
if [ "$current_commit" != "be2951ea34f0d295ed0becf97079f92fa5f6950e" ]; then
    echo "error: Codex checkout drifted from locked upstream be2951ea34f0d295ed0becf97079f92fa5f6950e: $current_commit" >&2
    exit 1
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
        echo "==> Applying $PATCH_NAME..."
        git -C "$SUBMODULE_DIR" apply "$PATCH_FILE"
    else
        patch_targets=()
        patch_target_list="$(mktemp)"
        { grep '^diff --git' "$PATCH_FILE" | sed 's|.*b/||'; grep '^--- a/' "$PATCH_FILE" | sed 's|^--- a/||'; } | sort -u > "$patch_target_list"
        while IFS= read -r pf; do
            [ -f "$SUBMODULE_DIR/$pf" ] && patch_targets+=("$SUBMODULE_DIR/$pf")
        done < "$patch_target_list"
        rm -f "$patch_target_list"
        added_lines="$(grep -m 5 '^+[^+]' "$PATCH_FILE" | sed 's/^+//' || true)"
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
            echo "error: $PATCH_NAME no longer applies cleanly to Codex $current_commit" >&2
            exit 1
        fi
    fi
done

echo "==> Installing Alley Cat mobile code-mode provider..."
python3 "$REPO_DIR/tools/scripts/patch-codex-mobile-code-mode.py" --codex-root "$SUBMODULE_DIR"

echo "==> codex submodule ready at $(git -C "$SUBMODULE_DIR" rev-parse --short HEAD)"
