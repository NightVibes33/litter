#!/usr/bin/env python3
"""Assert pinned native upstreams are reachable without replacing Alley Cat code.

Runs in the integration branch after recursive Git submodule checkout.
This is not a substitute for building the embedded frameworks or on-device tests.
"""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT / "ThirdParty/upstream-integration.json").read_text())

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()

def verify_gitlink(section, path_key):
    info = manifest[section]
    rel = info[path_key]
    expected = info["revision"]
    ls = git("ls-tree", "HEAD", "--", rel).split()
    if len(ls) < 3 or ls[0] != "160000" or ls[2] != expected:
        raise SystemExit(f"{section}: wrong gitlink for {rel} (expected {expected}): {ls}")
    actual = git("-C", rel, "rev-parse", "HEAD")
    if actual != expected:
        raise SystemExit(f"{section}: checked-out revision {actual} != {expected}")
    print(f"{section}: verified pinned upstream at {expected[:12]}")

def required(rel):
    path = ROOT / rel
    if not path.is_file():
        raise SystemExit(f"Missing required upstream/embedded source: {rel}")
    print(f"verified {rel}")

verify_gitlink("nyxian", "embedded_path")
verify_gitlink("sidestore", "upstream_path")
for rel in (
    "ThirdParty/EmexDE/Source/Frameworks/CoreCompiler/CoreCompiler.h",
    "ThirdParty/EmexDE/Source/Frameworks/MobileDevelopmentKit/MobileDevelopmentKit.h",
    "ThirdParty/EmexDE/Source/LLVM-On-iOS/Makefile",
    "ThirdParty/EmexDE/Source/Nyxian.xcodeproj/project.pbxproj",
    "ThirdParty/SideStore/Upstream/AltStore.xcodeproj/project.pbxproj",
    "ThirdParty/SideStore/Upstream/AltStore/Sources/AddSourceViewController.swift",
    "ThirdParty/SideStore/Upstream/Dependencies/SideSign/README.md",
    "ThirdParty/SideStore/Upstream/Dependencies/minimuxer/Cargo.toml",
    "ThirdParty/SideStore/Source/AltStore.xcodeproj/project.pbxproj",
    "ThirdParty/SideStore/Source/AltStore/Operations/UpdateKnownSourcesOperation.swift",
    "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitNative.h",
    "apps/ios/Sources/EmexDEEmbedded/EmexDEEmbeddedFactory.swift",
    "apps/ios/Sources/Litter/Views/SettingsView.swift",
):
    required(rel)
settings = (ROOT / "apps/ios/Sources/Litter/Views/SettingsView.swift").read_text()
if "SettingsRowLabel" not in settings or "settingsRowBackground()" not in settings:
    raise SystemExit("Alley Cat themed settings rows changed unexpectedly")
print("Pinned sources, dependency presence, and Alley Cat custom integration verified.")
