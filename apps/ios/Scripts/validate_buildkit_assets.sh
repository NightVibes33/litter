#!/bin/sh
set -eu
ROOT="$1"
MANIFEST="$ROOT/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "error: missing BuildKit manifest at $MANIFEST" >&2
  exit 1
fi
python3 - <<'PY' "$MANIFEST" "$ROOT"
import json, os, sys
manifest_path, root = sys.argv[1], sys.argv[2]
with open(manifest_path) as f:
    manifest = json.load(f)
required = manifest.get('requiredPaths', [])
missing = [p for p in required if not os.path.exists(os.path.join(root, p))]
if missing:
    raise SystemExit('missing required BuildKit paths:\n' + '\n'.join(missing))
print('BuildKit manifest valid with', len(required), 'required paths present')
PY
