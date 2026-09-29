#!/usr/bin/env python3
from __future__ import annotations
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "ThirdParty/EmexDE/Source"
LLVM = SOURCE / "LLVM-On-iOS"
LOCK_PATH = ROOT / "ThirdParty/EmexDE/UPSTREAM_LOCK.json"
PROJECT = ROOT / "apps/ios/project.yml"
WORKFLOW = ROOT / ".github/workflows/ios-unsigned-ipa.yml"
UPSTREAM_PROJECT = SOURCE / "Nyxian.xcodeproj/project.pbxproj"

def run(*args: str, cwd: pathlib.Path = ROOT) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()

def fail(message: str) -> None:
    raise SystemExit(message)

lock = json.loads(LOCK_PATH.read_text())
expected_nyxian = lock["nyxian"]["commit"]
expected_llvm = lock["llvmOnIOS"]["commit"]
expected_swift = lock["llvmOnIOS"]["swiftBranch"]

# The superproject gitlink, checked-out Nyxian worktree, nested LLVM gitlink,
# and checked-out LLVM worktree must all agree with the machine-readable lock.
actual_nyxian = run("git", "rev-parse", "HEAD", cwd=SOURCE)
super_gitlink = run("git", "ls-tree", "HEAD", "ThirdParty/EmexDE/Source").split()[2]
if actual_nyxian != expected_nyxian or super_gitlink != expected_nyxian:
    fail(f"Nyxian pin mismatch: lock={expected_nyxian} checkout={actual_nyxian} gitlink={super_gitlink}")

nested_gitlink = run("git", "ls-tree", "HEAD", "LLVM-On-iOS", cwd=SOURCE).split()[2]
actual_llvm = run("git", "rev-parse", "HEAD", cwd=LLVM)
if nested_gitlink != expected_llvm or actual_llvm != expected_llvm:
    fail(f"LLVM-On-iOS pin mismatch: lock={expected_llvm} gitlink={nested_gitlink} checkout={actual_llvm}")

makefile = (LLVM / "Makefile").read_text()
m = re.search(r"^SWIFT_BRANCH \?= (.+)$", makefile, re.M)
actual_swift = m.group(1).strip() if m else "missing"
if actual_swift != expected_swift:
    fail(f"Swift branch mismatch: expected {expected_swift}, Makefile={actual_swift}")

# Lock the COMPLETE upstream Package.resolved closure, not only the packages
# Alley Cat happens to reference directly. Any upstream package addition/removal
# must update the lock before CI can build.
resolved = json.loads(
    (SOURCE / "Nyxian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text()
)
pins = {p["identity"]: p["state"]["revision"] for p in resolved["pins"]}
locked_pins = {p["identity"]: p["revision"] for p in lock["swiftPackages"]}
if pins != locked_pins:
    missing = sorted(set(pins) - set(locked_pins))
    stale = sorted(set(locked_pins) - set(pins))
    mismatched = sorted(
        identity for identity in set(pins) & set(locked_pins)
        if pins[identity] != locked_pins[identity]
    )
    fail(
        "SwiftPM dependency closure mismatch: "
        f"unlocked={missing} stale={stale} revision_mismatch={mismatched}"
    )

project = PROJECT.read_text()
for package in lock["swiftPackages"]:
    block_pattern = re.compile(
        rf"(?ms)^  {re.escape(package['alias'])}:\n(?:(?:    .*\n)+?)(?=^  \S|^targets:)"
    )
    block_match = block_pattern.search(project)
    if not block_match:
        fail(f"apps/ios/project.yml is missing package alias {package['alias']}")
    if f"revision: {package['revision']}" not in block_match.group(0):
        fail(f"{package['alias']} is not pinned to upstream revision {package['revision']}")

# Every explicitly compiled/referenced path under the Nyxian submodule must
# exist in the exact locked checkout. Generated CoreCompilerSupportLibs are the
# only intentional exception because they are produced after this verifier.
path_re = re.compile(
    r"(?:path|framework): \..\/\.\.\/ThirdParty\/EmexDE\/Source\/([^#]+)$"
)
for lineno, raw in enumerate(project.splitlines(), 1):
    match = path_re.search(raw.strip())
    if not match:
        continue
    rel = match.group(1).strip().strip('"').strip("'")
    if "$(" in rel or "*" in rel:
        continue
    if rel.startswith("Frameworks/CoreCompiler/CoreCompilerSupportLibs"):
        continue
    if not (SOURCE / rel).exists():
        fail(f"apps/ios/project.yml:{lineno} references missing locked Nyxian path: {rel}")

for rel in lock["requiredSourcePaths"]:
    if not (SOURCE / rel).exists():
        fail(f"required upstream Nyxian path is missing: {rel}")

# The current upstream native target graph is part of the dependency closure.
# This catches renamed/removed runtime components before Litter's archive.
upstream_pbx = UPSTREAM_PROJECT.read_text()
upstream_targets = set(
    re.findall(r'Build configuration list for PBXNativeTarget "([^"]+)"', upstream_pbx)
)
missing_targets = sorted(set(lock["upstreamTargets"]) - upstream_targets)
if missing_targets:
    fail(f"locked Nyxian native targets are missing upstream: {missing_targets}")

# CI must install every native prerequisite declared by the lock.
workflow = WORKFLOW.read_text()
install_match = re.search(
    r"(?ms)^      - name: Install native build dependencies\n(.*?)(?=^      - name:|\Z)",
    workflow,
)
if not install_match:
    fail("iOS workflow is missing the native dependency installation step")
install_block = install_match.group(1)
missing_tools = [
    dep for dep in lock["nativeBuildDependencies"]
    if not re.search(rf"(?<![A-Za-z0-9_.+-]){re.escape(dep)}(?![A-Za-z0-9_.+-])", install_block)
]
if missing_tools:
    fail(f"iOS workflow does not install locked Nyxian native dependencies: {missing_tools}")

# Runtime binaries must be both produced from upstream Nyxian and embedded by
# Alley Cat. This verifies names from one lock instead of duplicated assumptions.
runtime_builder = (ROOT / "tools/scripts/build-emexde-upstream-runtime.sh").read_text()
for binary in lock["runtimeBinaries"]:
    if binary not in runtime_builder:
        fail(f"runtime builder does not produce locked Nyxian binary: {binary}")
    if binary not in project:
        fail(f"apps/ios/project.yml does not embed/reference locked Nyxian binary: {binary}")
    if binary not in workflow:
        fail(f"iOS workflow does not validate locked Nyxian binary: {binary}")

dirty = run("git", "status", "--porcelain", "--untracked-files=no", cwd=SOURCE)
if dirty:
    fail("Nyxian tracked sources are dirty before integration build:\n" + dirty)

print(f"Verified exact Nyxian upstream closure: {expected_nyxian}")
print(f"  LLVM-On-iOS: {expected_llvm} ({expected_swift})")
print(f"  SwiftPM closure: {len(locked_pins)} exact revisions")
print(f"  Native prerequisites: {', '.join(lock['nativeBuildDependencies'])}")
print(f"  Native targets: {', '.join(lock['upstreamTargets'])}")
print(f"  Runtime binaries: {', '.join(lock['runtimeBinaries'])}")
print(f"  Required source/resource paths: {len(lock['requiredSourcePaths'])}")
