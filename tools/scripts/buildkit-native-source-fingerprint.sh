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
    "ThirdParty/Nyxian/MobileDevelopmentKit/Support",
    "ThirdParty/Nyxian/MobileDevelopmentKit/Tools",
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
