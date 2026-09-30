#!/usr/bin/env python3
"""Verify the pristine SideStore source closure without replacing KittyStore UI."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def canonical(url: str) -> str:
    return url.rstrip("/").removesuffix(".git").lower()


def pins(path: Path) -> dict:
    data = json.loads(path.read_text())
    return {p["identity"]: (canonical(p["location"]), p["state"]["revision"])
            for p in data["pins"]}


def verify(root: Path, lock: dict) -> None:
    expected = lock["sideStore"]["commit"]
    if not (root / ".git").exists():
        raise ValueError(f"SideStore upstream submodule not initialized: {root}")
    if git(root, "rev-parse", "HEAD") != expected:
        raise ValueError("SideStore upstream checkout differs from the exact lock")
    for rel in lock["requiredPaths"]:
        if not (root / rel).exists():
            raise ValueError(f"Missing locked SideStore source/resource: {rel}")

    links = {}
    for line in git(root, "ls-tree", "-r", "HEAD").splitlines():
        meta, path = line.split("\t", 1)
        mode, kind, sha = meta.split()
        if mode == "160000":
            links[path] = sha
    expected_links = {p["path"]: p["commit"] for p in lock["nestedGitlinks"]}
    if links != expected_links:
        raise ValueError(f"SideStore nested gitlink closure mismatch: {links}")
    for item in lock["nestedGitlinks"]:
        path = root / item["path"]
        if git(path, "rev-parse", "HEAD") != item["commit"]:
            raise ValueError(f"Nested dependency checkout mismatch: {item['path']}")
        url = git(root, "config", "-f", ".gitmodules", "--get",
                  f"submodule.{item['path']}.url")
        if canonical(url) != canonical(item["repository"]):
            raise ValueError(f"Nested dependency repository mismatch: {item['path']}")
        if git(path, "status", "--porcelain", "--untracked-files=no"):
            raise ValueError(f"Nested upstream sources modified: {item['path']}")

    scopes = {
        "sideStore": root / "AltStore.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        "minimuxer": root / "Dependencies/minimuxer/Package.resolved",
        "sideSign": root / "Dependencies/SideSign/Package.resolved",
    }
    for scope, path in scopes.items():
        expected_pins = {p["identity"]: (canonical(p["location"]), p["revision"])
                         for p in lock["swiftPM"][scope]}
        if pins(path) != expected_pins:
            raise ValueError(f"SwiftPM repository/revision closure mismatch: {scope}")

    for artifact in lock["binaryArtifacts"]:
        manifest = root / "Dependencies" / artifact["package"] / "Package.swift"
        text = re.sub(r"(?m)^\s*//.*$", "", manifest.read_text())
        blocks = re.findall(r"\.binaryTarget\s*\((.*?)\)", text, re.S)
        found = [b for b in blocks if f'"{artifact["target"]}"' in b]
        if len(found) != 1 or artifact["url"] not in found[0] or artifact["checksum"] not in found[0]:
            raise ValueError(f"Binary artifact URL/checksum mismatch: {artifact['target']}")
    if git(root, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Pristine SideStore upstream checkout is dirty")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--require-embedded", action="store_true")
    args = parser.parse_args()
    lock = json.loads((ROOT / "ThirdParty/SideStore/UPSTREAM_LOCK.json").read_text())
    root = args.source_root or ROOT / lock["sourcePath"]
    try:
        verify(root, lock)
        if not args.source_root:
            link = git(ROOT, "ls-tree", "HEAD", lock["sourcePath"]).split()
            if len(link) < 3 or link[0] != "160000" or link[2] != lock["sideStore"]["commit"]:
                raise ValueError("Superproject SideStore gitlink differs from lock")
        if args.require_embedded and lock["integrationStatus"] != "embedded-verified":
            raise ValueError("Upstream closure exists, but embedded KittyStore runtime migration is still pending")
    except (ValueError, subprocess.CalledProcessError, OSError, KeyError) as error:
        raise SystemExit(f"SideStore closure verification failed: {error}") from error
    print(f"Verified exact SideStore upstream closure: {lock['sideStore']['commit']}")
    print(f"Nested gitlinks: {len(lock['nestedGitlinks'])}; binary artifact locks: {len(lock['binaryArtifacts'])}")
    print(f"Embedded KittyStore migration: {lock['integrationStatus']}")


if __name__ == "__main__":
    main()
