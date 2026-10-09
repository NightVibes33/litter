#!/usr/bin/env python3
"""Validate isolated upstream pins and custom Alley Cat compatibility surface."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
lock = json.loads((ROOT / "ThirdParty/UPSTREAM_INTEGRATION_LOCK.json").read_text())

def git(path, *args):
    return subprocess.check_output(
        ["git", "-C", str(path), *args], text=True, stderr=subprocess.STDOUT
    ).strip()

def require(condition, message):
    if not condition:
        raise SystemExit("upstream verification failed: " + message)

def verify_gitlink(entry, key):
    tracked = git(ROOT, "ls-tree", "HEAD", entry["path"] if key == "nyxian" else entry["sourcePath"])
    expected = entry["target"] if key == "nyxian" else entry["upstreamTarget"]
    require(f"160000 commit {expected}" in tracked, f"{key} pinned gitlink mismatch")
    path = ROOT / (entry["path"] if key == "nyxian" else entry["sourcePath"])
    require((path / ".git").exists(), f"{key} submodule not checked out")
    require(git(path, "rev-parse", "HEAD") == expected, f"{key} checkout SHA mismatch")
    print(f"{key}: checked out {expected}")

verify_gitlink(lock["nyxian"], "nyxian")
verify_gitlink(lock["sideStore"], "sideStore")
nyx = ROOT / lock["nyxian"]["path"]
sidestore = ROOT / lock["sideStore"]["sourcePath"]
for path in ["LLVM-On-iOS/Makefile", "Nyxian.xcodeproj/project.pbxproj"]:
    require((nyx / path).is_file(), "upstream Nyxian missing " + path)
for path in ["SideStore", "AltStore/Core", "Dependencies/SideSign", "Dependencies/minimuxer"]:
    require((sidestore / path).exists(), "upstream SideStore missing " + path)
for path in [
    "ThirdParty/SideStore/Source/AltStoreCore",
    "ThirdParty/SideStore/Source/AltStore/TabBarController.swift",
    "apps/ios/Sources/KittyStoreEmbedded/KittyStoreEmbeddedFactory.swift",
    "apps/ios/Sources/EmexDEEmbedded/EmexDEEmbeddedFactory.swift",
    "apps/ios/Sources/Litter/Views/SettingsView.swift",
]:
    require((ROOT / path).exists(), "Alley Cat compatibility code missing " + path)
print("Upstream snapshots and Alley Cat compatibility files present.")
print("NOTE: This does NOT assert SideStore's new architecture is integrated or IPA boots.")
