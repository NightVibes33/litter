#!/usr/bin/env python3
from __future__ import annotations
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "ThirdParty/EmexDE/Source"
LLVM = SOURCE / "LLVM-On-iOS"
LOCK_PATH = ROOT / "ThirdParty/EmexDE/UPSTREAM_LOCK.json"
PROJECT = ROOT / "apps/ios/project.yml"

def run(*args: str, cwd: pathlib.Path = ROOT) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()

lock = json.loads(LOCK_PATH.read_text())
expected_nyxian = lock["nyxian"]["commit"]
expected_llvm = lock["llvmOnIOS"]["commit"]
expected_swift = lock["llvmOnIOS"]["swiftBranch"]

actual_nyxian = run("git", "rev-parse", "HEAD", cwd=SOURCE)
super_gitlink = run("git", "ls-tree", "HEAD", "ThirdParty/EmexDE/Source").split()[2]
if actual_nyxian != expected_nyxian or super_gitlink != expected_nyxian:
    raise SystemExit(f"Nyxian pin mismatch: lock={expected_nyxian} checkout={actual_nyxian} gitlink={super_gitlink}")

nested_gitlink = run("git", "ls-tree", "HEAD", "LLVM-On-iOS", cwd=SOURCE).split()[2]
actual_llvm = run("git", "rev-parse", "HEAD", cwd=LLVM)
if nested_gitlink != expected_llvm or actual_llvm != expected_llvm:
    raise SystemExit(f"LLVM-On-iOS pin mismatch: lock={expected_llvm} gitlink={nested_gitlink} checkout={actual_llvm}")

makefile = (LLVM / "Makefile").read_text()
m = re.search(r"^SWIFT_BRANCH \?= (.+)$", makefile, re.M)
if not m or m.group(1).strip() != expected_swift:
    raise SystemExit(f"Swift branch mismatch: expected {expected_swift}, Makefile={m.group(1).strip() if m else 'missing'}")

resolved = json.loads((SOURCE / "Nyxian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
pins = {p["identity"]: p["state"]["revision"] for p in resolved["pins"]}
for package in lock["swiftPackages"]:
    got = pins.get(package["identity"])
    if got != package["revision"]:
        raise SystemExit(f"SwiftPM pin mismatch for {package['identity']}: lock={package['revision']} upstream={got}")

project = PROJECT.read_text()
for package in lock["swiftPackages"]:
    block_pattern = re.compile(
        rf"(?ms)^  {re.escape(package['alias'])}:\n(?:(?:    .*\n)+?)(?=^  \S|^targets:)"
    )
    block_match = block_pattern.search(project)
    if not block_match:
        raise SystemExit(f"apps/ios/project.yml is missing package alias {package['alias']}")
    block = block_match.group(0)
    if f"revision: {package['revision']}" not in block:
        raise SystemExit(f"{package['alias']} is not pinned to upstream revision {package['revision']}")

required_paths = [
    "Frameworks/CoreCompiler/Tools/CCDriver.cpp",
    "Frameworks/CoreCompiler/Tools/Compiler/CCSwiftCompiler.cpp",
    "Frameworks/MobileDevelopmentKit/MobileDevelopmentKit.h",
    "Frameworks/LiveShim/LiveShim.h",
    "Frameworks/Broadpatch/Broadpatch.m",
    "Daemons/bootstrapd/main.m",
    "Daemons/MobileDevelopmentService/main.m",
    "LiveProcess/main.m",
    "Nyxian/UI/BootViewController.swift",
    "Nyxian/LindChain/ProcEnvironment/Surface/fs/fs.m",
]
for rel in required_paths:
    if not (SOURCE / rel).exists():
        raise SystemExit(f"required upstream Nyxian path is missing: {rel}")

dirty = run("git", "status", "--porcelain", "--untracked-files=no", cwd=SOURCE)
if dirty:
    raise SystemExit("Nyxian tracked sources are dirty before integration build:\n" + dirty)

print(f"Verified exact Nyxian upstream closure: {expected_nyxian}")
print(f"  LLVM-On-iOS: {expected_llvm} ({expected_swift})")
print(f"  SwiftPM pins: {len(lock['swiftPackages'])}")
print(f"  Runtime binaries: {', '.join(lock['runtimeBinaries'])}")
