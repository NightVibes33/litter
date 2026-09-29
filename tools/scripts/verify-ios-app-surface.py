#!/usr/bin/env python3
from __future__ import annotations
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCK = ROOT / "tools/upstream/ios-app-surface-lock.json"

def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()

data = json.loads(LOCK.read_text())
failures: list[str] = []
for item in data["files"]:
    rel = item["path"]
    expected = item["sha"]
    path = ROOT / rel
    if not path.is_file():
        failures.append(f"missing protected app-surface file: {rel}")
        continue
    actual = git("hash-object", "--", rel)
    if actual != expected:
        failures.append(f"protected app-surface drift: {rel} expected {expected} got {actual}")

if failures:
    print("\n".join(f"error: {line}" for line in failures), file=sys.stderr)
    raise SystemExit(1)

print(f"Protected Alley Cat iOS app surface unchanged: {len(data['files'])} files")
