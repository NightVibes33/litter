#!/usr/bin/env sh
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
exec python3 "$ROOT_DIR/tools/scripts/vendor-nyxian.py"
