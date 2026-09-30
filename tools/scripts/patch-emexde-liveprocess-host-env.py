#!/usr/bin/env python3
"""Keep Nyxian LiveProcess HOST_ENV process teardown behind the declaration gate.

Nyxian's LDEApplicationWorkspace conditionally imports PEProcessManager only when
Nyxian-Swift.h is available, but its uninstall teardown was guarded by HOST_ENV
alone. In Alley Cat's LiveShim build HOST_ENV is true while Nyxian-Swift.h is
intentionally absent, leaving PEProcess/PEProcessManager undeclared.
"""
from pathlib import Path

path = Path("ThirdParty/EmexDE/Source/LiveProcess/LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.m")
text = path.read_text()
needle = """- (void)applicationWithBundleIdentifierWasUninstalled:(NSString*)bundleIdentifier
{
#if HOST_ENV
    PEProcess *process = [[PEProcessManager shared] processForBundleIdentifier:bundleIdentifier];"""
replacement = """- (void)applicationWithBundleIdentifierWasUninstalled:(NSString*)bundleIdentifier
{
#if HOST_ENV && __has_include(<Nyxian-Swift.h>)
    PEProcess *process = [[PEProcessManager shared] processForBundleIdentifier:bundleIdentifier];"""
if replacement in text:
    print(f"{path}: already patched")
elif needle in text:
    path.write_text(text.replace(needle, replacement, 1))
    print(f"{path}: patched HOST_ENV process teardown guard")
else:
    raise SystemExit(f"error: expected Nyxian source pattern not found in {path}")
