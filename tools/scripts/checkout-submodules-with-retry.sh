#!/usr/bin/env bash
set -euo pipefail

max_attempts="${SUBMODULE_CHECKOUT_ATTEMPTS:-4}"
jobs="${SUBMODULE_CHECKOUT_JOBS:-1}"

git submodule sync --recursive

attempt=1
while [[ "$attempt" -le "$max_attempts" ]]; do
    echo "==> Checking out submodules (attempt $attempt/$max_attempts, jobs=$jobs)"
    if git -c protocol.version=2 submodule update --init --force --recursive --depth 1 --jobs "$jobs"; then
        exit 0
    fi

    if [[ "$attempt" -eq "$max_attempts" ]]; then
        break
    fi

    echo "Submodule checkout failed; cleaning partial submodule worktrees before retry."
    git submodule foreach --recursive 'git reset --hard || true; git clean -fdx || true' || true
    sleep "$((attempt * 20))"
    attempt="$((attempt + 1))"
done

echo "Shallow submodule checkout failed after $max_attempts attempts; retrying once without --depth." >&2
git -c protocol.version=2 submodule update --init --force --recursive --jobs 1
