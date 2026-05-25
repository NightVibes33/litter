#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
NYXIAN_REPO="${NYXIAN_REPO:-https://github.com/ProjectNyxian/Nyxian}"
NYXIAN_COMMIT="${NYXIAN_COMMIT:-d955607acf4e8112c28d1db01837fc3e11631de3}"
NYXIAN_DEST="${NYXIAN_DEST:-$ROOT_DIR/ThirdParty/Nyxian}"
TMP_DIR="${TMPDIR:-/tmp}/litter-vendor-nyxian-$$"
REPO_PATH="$(printf '%s' "$NYXIAN_REPO" | sed -E 's#^https://github.com/##; s#^git@github.com:##; s#\.git$##')"
ARCHIVE_URL="${NYXIAN_ARCHIVE_URL:-https://codeload.github.com/$REPO_PATH/tar.gz/$NYXIAN_COMMIT}"
CODELOAD_IP="${LITTER_CODELOAD_RESOLVE_IP:-}"
if [ -z "$CODELOAD_IP" ]; then
  CODELOAD_IP="$(getent hosts codeload.github.com 2>/dev/null | awk 'NR==1 {print $1}' || true)"
fi
if [ -z "$CODELOAD_IP" ]; then
  CODELOAD_IP="140.82.114.9"
fi

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP_DIR" "$(dirname "$NYXIAN_DEST")"
printf '%s\n' "==> Downloading Nyxian $NYXIAN_COMMIT"
printf '%s\n' "==> Source: $ARCHIVE_URL"
mkdir -p "$TMP_DIR/archive"
if curl -L --fail --retry 3 --connect-timeout 30 --resolve "codeload.github.com:443:$CODELOAD_IP" --output "$TMP_DIR/nyxian.tar.gz" "$ARCHIVE_URL"; then
  tar -xzf "$TMP_DIR/nyxian.tar.gz" -C "$TMP_DIR/archive"
  SRC_DIR="$(find "$TMP_DIR/archive" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
else
  echo "warning: archive download failed; falling back to GitHub API/raw import" >&2
  SRC_DIR="$TMP_DIR/archive/Nyxian-$NYXIAN_COMMIT"
  mkdir -p "$SRC_DIR"
  python3 - "$NYXIAN_REPO" "$NYXIAN_COMMIT" "$SRC_DIR" <<'PYRAW'
import json, sys, time, urllib.parse, urllib.request
from pathlib import Path
repo_url, commit, dest = sys.argv[1], sys.argv[2], Path(sys.argv[3])
parts = urllib.parse.urlparse(repo_url)
repo_path = parts.path.strip('/')
if repo_url.startswith('git@github.com:'):
    repo_path = repo_url.split(':', 1)[1]
if repo_path.endswith('.git'):
    repo_path = repo_path[:-4]
api = f'https://api.github.com/repos/{repo_path}/git/trees/{commit}?recursive=1'
headers = {'User-Agent': 'litter-vendor-nyxian'}

def fetch(url):
    last = None
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=60) as response:
                return response.read()
        except Exception as exc:
            last = exc
            time.sleep(1 + attempt)
    raise last

tree = json.loads(fetch(api).decode('utf-8'))
if tree.get('truncated'):
    raise SystemExit('GitHub tree response was truncated')
exclude_dir_parts = {'.git', '.github'}
exclude_suffixes = ('.xcframework/', '.framework/')
exclude_file_suffixes = ('.ipa', '.mobileprovision', '.p12', '.cer', '.zip', '.png')
blobs = [entry['path'] for entry in tree.get('tree', []) if entry.get('type') == 'blob']
kept = 0
for rel in blobs:
    parts = rel.split('/')
    if any(part in exclude_dir_parts for part in parts):
        continue
    rel_slash = rel + '/'
    if any(suffix in rel_slash for suffix in exclude_suffixes):
        continue
    if rel.endswith(exclude_file_suffixes):
        continue
    target = dest / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    raw = f'https://raw.githubusercontent.com/{repo_path}/{commit}/{urllib.parse.quote(rel)}'
    target.write_bytes(fetch(raw))
    kept += 1
print(f'imported {kept} upstream blob entries via raw API')
PYRAW
fi
if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  echo "error: downloaded Nyxian archive did not contain a source directory" >&2
  exit 1
fi

if [ -d "$NYXIAN_DEST/LitterBuildKitNative" ]; then
  mkdir -p "$TMP_DIR/preserve"
  cp -R "$NYXIAN_DEST/LitterBuildKitNative" "$TMP_DIR/preserve/LitterBuildKitNative"
fi

rm -rf "$NYXIAN_DEST"
mkdir -p "$NYXIAN_DEST"
python3 - "$SRC_DIR" "$NYXIAN_DEST" <<'PYCOPY'
import shutil, sys
from pathlib import Path
src = Path(sys.argv[1])
dst = Path(sys.argv[2])
exclude_dirs = {'.git', '.github', 'Assets.xcassets', 'Preview Content'}
exclude_dir_suffixes = ('.framework', '.xcframework')
exclude_file_suffixes = ('.ipa', '.mobileprovision', '.p12', '.cer', '.zip', '.png')

def skip(path: Path) -> bool:
    if any(part in exclude_dirs for part in path.parts):
        return True
    if path.is_dir() and path.name.endswith(exclude_dir_suffixes):
        return True
    if path.is_file() and path.name.endswith(exclude_file_suffixes):
        return True
    return False

for item in src.iterdir():
    if skip(item):
        continue
    target = dst / item.name
    if item.is_dir():
        def ignore(directory, names):
            ignored = []
            d = Path(directory)
            for name in names:
                p = d / name
                if skip(p):
                    ignored.append(name)
            return ignored
        shutil.copytree(item, target, symlinks=True, ignore=ignore)
    else:
        shutil.copy2(item, target, follow_symlinks=False)
PYCOPY

if [ -d "$TMP_DIR/preserve/LitterBuildKitNative" ]; then
  rm -rf "$NYXIAN_DEST/LitterBuildKitNative"
  cp -R "$TMP_DIR/preserve/LitterBuildKitNative" "$NYXIAN_DEST/LitterBuildKitNative"
fi

cat > "$NYXIAN_DEST/LITTER_NYXIAN_IMPORT.json" <<IMPORTJSON
{
  "repository": "$NYXIAN_REPO",
  "commit": "$NYXIAN_COMMIT",
  "archiveUrl": "$ARCHIVE_URL",
  "preservedLocalPaths": [
    "LitterBuildKitNative"
  ],
  "excludedFromVendorArchive": [
    ".git",
    ".github",
    "*.framework",
    "*.xcframework",
    "*.ipa",
    "*.mobileprovision",
    "*.p12",
    "*.cer",
    "*.zip",
    "*.png",
    "Assets.xcassets",
    "Preview Content"
  ],
  "submodules": {
    "LLVM-On-iOS": "https://github.com/ProjectNyxian/LLVM-On-iOS.git",
    "libroot": "https://github.com/Opa334/libroot.git",
    "TrollStore": "https://github.com/opa334/TrollStore"
  }
}
IMPORTJSON

printf '%s\n' "==> Nyxian source imported into $NYXIAN_DEST"
printf '%s\n' "==> Preserved Litter bridge: $NYXIAN_DEST/LitterBuildKitNative"
