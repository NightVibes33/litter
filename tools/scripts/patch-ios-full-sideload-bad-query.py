#!/usr/bin/env python3
"""Inject exact bad_query integration into full Nyxian sideload builds.

Unlike patch-ios-fast-device-project.py, this patch must not remove emexDE,
CoreCompiler, MobileDevelopmentKit, LiveProcess, or their package/dependency
wiring. It reuses the exact bad_query agent/bridge validation from the fast
unsigned patch while limiting the project.yml change to one correctly placed
UnsignedOnly/BadQuery source entry.
"""

from __future__ import annotations

import argparse
import runpy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FAST_PATCH = ROOT / "tools/scripts/patch-ios-fast-device-project.py"
PROJECT_YML = ROOT / "apps/ios/project.yml"
APPLE_AGENT = ROOT / "apps/ios/Sources/Litter/Models/AppleOnDeviceAgent.swift"
APPLE_BRIDGE = ROOT / "apps/ios/Sources/Litter/Views/AppleLocalAgentBridge.swift"
BRIDGING_HEADER = ROOT / "apps/ios/Sources/Litter/Bridge/codex_bridge_objc.h"

helpers = runpy.run_path(str(FAST_PATCH))
transform_apple_agent = helpers["transform_apple_agent"]
transform_apple_bridge = helpers["transform_apple_bridge"]
transform_bridging_header = helpers["transform_bridging_header"]
validate_bad_query_agent = helpers["validate_bad_query_agent"]
UNSIGNED_BAD_QUERY_SOURCE = helpers["UNSIGNED_BAD_QUERY_SOURCE"]


NYXIAN_MARKERS = (
    "  CoreCompiler:\n",
    "  MobileDevelopmentKit:\n",
    "  emexDE:\n",
    "  LiveProcess:\n",
    "      - target: CoreCompiler\n        embed: true\n        link: false\n",
    "      - target: MobileDevelopmentKit\n        embed: true\n        link: false\n",
    "      - target: emexDE\n        embed: true\n        link: false\n",
    "      - target: LiveProcess\n        embed: true\n",
)

LITTER_SOURCE_MARKER = "      - path: Sources/Litter\n"
LITTER_MINIMUXER_EXCLUDE = "          - Generated/Minimuxer/**\n"


def add_full_sideload_bad_query_source(text: str) -> str:
    if UNSIGNED_BAD_QUERY_SOURCE in text:
        return text

    lines = text.splitlines(keepends=True)
    try:
        source_index = lines.index(LITTER_SOURCE_MARKER)
    except ValueError as error:
        raise SystemExit("Full sideload bad_query patch could not locate the Litter source entry") from error

    insert_index = source_index + 1
    while insert_index < len(lines):
        line = lines[insert_index]
        if line.startswith("      - path:") or line.startswith("    resources:"):
            break
        insert_index += 1

    source_block = "".join(lines[source_index:insert_index])
    if "        excludes:\n" not in source_block or LITTER_MINIMUXER_EXCLUDE not in source_block:
        raise SystemExit(
            "Full sideload bad_query patch refused to run because the Litter generated-Minimuxer exclusion is not attached to Sources/Litter"
        )

    lines.insert(insert_index, UNSIGNED_BAD_QUERY_SOURCE)
    return "".join(lines)


def transform_full_sideload_project(text: str) -> str:
    for marker in NYXIAN_MARKERS:
        if marker not in text:
            raise SystemExit(
                "Full sideload bad_query patch refused to run because Nyxian/emexDE wiring is missing: "
                + marker.strip()
            )

    patched = add_full_sideload_bad_query_source(text)

    for marker in NYXIAN_MARKERS:
        if marker not in patched:
            raise SystemExit(
                "Full sideload bad_query patch removed Nyxian/emexDE wiring unexpectedly: "
                + marker.strip()
            )

    if UNSIGNED_BAD_QUERY_SOURCE not in patched:
        raise SystemExit("Full sideload bad_query patch failed to add UnsignedOnly/BadQuery to the Litter source list")

    # Ensure the existing Litter exclusions remain attached to Sources/Litter.
    litter_source_start = patched.index(LITTER_SOURCE_MARKER)
    bad_query_index = patched.index(UNSIGNED_BAD_QUERY_SOURCE, litter_source_start)
    litter_source_block = patched[litter_source_start:bad_query_index]
    if LITTER_MINIMUXER_EXCLUDE not in litter_source_block:
        raise SystemExit("Full sideload bad_query patch detached the generated KittyStore minimuxer exclusion")

    # The full-sideload project transform is intentionally surgical: the only
    # allowed project.yml change is the unsigned BadQuery source entry.
    if UNSIGNED_BAD_QUERY_SOURCE not in text:
        restored = patched.replace(UNSIGNED_BAD_QUERY_SOURCE, "", 1)
        if restored != text:
            raise SystemExit("Full sideload bad_query patch changed project.yml beyond the unsigned source entry")

    return patched


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate transformed output without writing")
    args = parser.parse_args()

    original_project = PROJECT_YML.read_text()
    original_agent = APPLE_AGENT.read_text()
    original_bridge = APPLE_BRIDGE.read_text()
    original_header = BRIDGING_HEADER.read_text()

    patched_project = transform_full_sideload_project(original_project)
    patched_agent = transform_apple_agent(original_agent)
    patched_bridge = transform_apple_bridge(original_bridge)
    patched_header = transform_bridging_header(original_header)

    validate_bad_query_agent(patched_agent, patched_bridge, patched_header)

    if args.check:
        print("Full Nyxian sideload + exact bad_query integration is valid; Nyxian/emexDE wiring and Litter source exclusions are preserved.")
        return

    changed = False
    for path, original, patched in (
        (PROJECT_YML, original_project, patched_project),
        (APPLE_AGENT, original_agent, patched_agent),
        (APPLE_BRIDGE, original_bridge, patched_bridge),
        (BRIDGING_HEADER, original_header, patched_header),
    ):
        if patched != original:
            path.write_text(patched)
            changed = True

    if changed:
        print(
            "Applied full-sideload bad_query patch: exact upstream bad_query is injected while "
            "CoreCompiler, MobileDevelopmentKit, emexDE, LiveProcess, and Litter source exclusions remain enabled."
        )
    else:
        print("Full-sideload exact bad_query integration already applied.")


if __name__ == "__main__":
    main()
