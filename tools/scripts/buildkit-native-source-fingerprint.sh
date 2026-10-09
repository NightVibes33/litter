#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import hashlib
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
paths = [
    "ThirdParty/Nyxian/LitterBuildKitNative",
    "ThirdParty/Feather/Zsign-Package/src",
    # The embedded runtime owns MDK; do not fingerprint stale vendor headers.
    "ThirdParty/EmexDE/Source",
    "tools/scripts/build-litter-buildkit-native.sh",
    "tools/scripts/package-buildkit-assets.sh",
    "tools/scripts/verify-nyxian-buildkit-assets.sh",
    "tools/scripts/buildkit-native-source-fingerprint.sh",
]

def git_files():
    try:
        data = subprocess.check_output(
            ["git", "-C", str(root), "ls-files", "-z", "--", *paths],
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return []
    return sorted(path for path in data.decode("utf-8", "surrogateescape").split("\0") if path)

def fallback_files():
    selected = []
    for rel in paths:
        path = root / rel
        if path.is_file():
            selected.append(rel)
        elif path.is_dir():
            for child in path.rglob("*"):
                if child.is_file() and not child.is_symlink():
                    selected.append(child.relative_to(root).as_posix())
    return sorted(set(selected))

files = git_files() or fallback_files()
if not files:
    raise SystemExit("error: no BuildKit native source files found for fingerprinting")

digest = hashlib.sha256()
# The parent index stores submodules as gitlinks. Include both checked-out
# source revisions so the native bridge cache cannot mix compiler ABIs.
for rel in ("ThirdParty/EmexDE/Source", "ThirdParty/EmexDE/Source/LLVM-On-iOS"):
    revision = subprocess.check_output(
        ["git", "-C", str(root / rel), "rev-parse", "HEAD"], text=True
    ).strip()
    digest.update(rel.encode("utf-8") + b"\0" + revision.encode("ascii") + b"\n")
for rel in files:
    path = root / rel
    if not path.is_file():
        continue
    data = path.read_bytes()
    digest.update(rel.encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(len(data)).encode("ascii"))
    digest.update(b"\0")
    digest.update(hashlib.sha256(data).hexdigest().encode("ascii"))
    digest.update(b"\n")

print(digest.hexdigest())
PY
