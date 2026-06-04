#!/usr/bin/env python3
"""Patch the generated iOS project spec for fast TestFlight builds.

The TestFlight experiment still embeds the full KittyStore/SideStore path, but
the hidden emexDE/BuildKit support targets are skipped so the lane stays fast.
This script is intentionally text-based because XcodeGen's project.yml is the
source of truth and PyYAML is not guaranteed on GitHub's runner image.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = ROOT / "apps/ios/project.yml"

DEPENDENCY_BLOCKS = (
    """      - target: CoreCompiler
        embed: true
        link: false
""",
    """      - target: MobileDevelopmentKit
        embed: true
        link: false
""",
    """      - target: emexDE
        embed: true
        link: false
""",
    """      - target: LiveProcess
        embed: true
""",
)

POST_BUILD_SCRIPT_NAMES = (
    "Embed emexDE Runtime Resources",
    "Package Private BuildKit Assets",
    "Embed Private BuildKit Frameworks",
)

FAST_TARGET_NAMES = (
    "CoreCompiler",
    "MobileDevelopmentKit",
    "emexDE",
    "LiveProcess",
)


def remove_named_yaml_section(text: str, marker: str) -> str:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    index = 0
    while index < len(lines):
        if lines[index] == marker:
            index += 1
            while index < len(lines):
                line = lines[index]
                if line.startswith("  ") and not line.startswith("    "):
                    break
                if line and not line.startswith(" ") and line.strip():
                    break
                index += 1
            continue
        output.append(lines[index])
        index += 1
    return "".join(output)


def remove_named_post_build_script(text: str, name: str) -> str:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    index = 0
    marker = f"      - name: {name}\n"
    while index < len(lines):
        if lines[index] == marker:
            index += 1
            while index < len(lines):
                line = lines[index]
                if line.startswith("      - name: ") or line.startswith("    settings:"):
                    break
                index += 1
            continue
        output.append(lines[index])
        index += 1
    return "".join(output)


def transform(text: str) -> str:
    text = text.replace("        PRODUCT_NAME: Littër\n", "        PRODUCT_NAME: Litter\n")

    for target in FAST_TARGET_NAMES:
        text = remove_named_yaml_section(text, f"  {target}:\n")

    for block in DEPENDENCY_BLOCKS:
        text = text.replace(block, "")

    text = text.replace(
        "          embed_emexde_corecompiler_artifacts\n"
        "          embed_framework_if_present CoreCompiler 1\n",
        '          echo "Skipping emexDE CoreCompiler embedding for fast TestFlight"\n',
    )
    text = text.replace(
        '          copy_upstream_source emexDE "$SRCROOT/../../ThirdParty/EmexDE/Source"\n',
        "",
    )

    for name in POST_BUILD_SCRIPT_NAMES:
        text = remove_named_post_build_script(text, name)

    return text


def validate_fast_project(text: str) -> None:
    failures: list[str] = []
    for target in FAST_TARGET_NAMES:
        if f"  {target}:\n" in text:
            failures.append(f"still has target definition: {target}")

    for block in DEPENDENCY_BLOCKS:
        if block in text:
            first = block.strip().splitlines()[0].strip()
            failures.append(f"still has Litter dependency block: {first}")

    for name in POST_BUILD_SCRIPT_NAMES:
        if f"      - name: {name}\n" in text:
            failures.append(f"still has post-build script: {name}")

    if re.search(r"^          embed_emexde_corecompiler_artifacts$", text, re.MULTILINE):
        failures.append("still calls embed_emexde_corecompiler_artifacts")
    if re.search(r"^          embed_framework_if_present CoreCompiler 1$", text, re.MULTILINE):
        failures.append("still requires CoreCompiler.framework embedding")
    if "copy_upstream_source emexDE" in text:
        failures.append("still copies emexDE upstream source")
    if "        PRODUCT_NAME: Littër\n" in text:
        failures.append("still uses non-ASCII iOS PRODUCT_NAME")

    required_kept = (
        "        INFOPLIST_KEY_LitterEmbedsSideStore: \"YES\"\n",
        "  SideStore:\n",
        "  AltStoreCore:\n",
        "  Roxas:\n",
        "  Minimuxer:\n",
        "  RustBridge:\n",
        "      - target: SideStore\n        embed: true\n",
        "        product: AltSign-Dynamic\n",
        "          embed_framework_if_present AltSign-Dynamic 1\n",
        "          embed_framework_if_present AltStoreCore 1\n",
        "          embed_framework_if_present Roxas 1\n",
        "          embed_framework_if_present Minimuxer 1\n",
        "          embed_framework_if_present RustBridge 1\n",
    )
    for marker in required_kept:
        if marker not in text:
            failures.append(f"removed KittyStore dependency unexpectedly: {marker.strip()}")

    if failures:
        raise SystemExit("Fast TestFlight project patch failed:\n- " + "\n- ".join(failures))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate the transformed output without writing")
    args = parser.parse_args()

    original = PROJECT_YML.read_text()
    patched = transform(original)
    validate_fast_project(patched)

    if args.check:
        print("Fast TestFlight project patch is valid.")
        return

    if patched == original:
        print("Fast TestFlight project patch already applied.")
        return

    PROJECT_YML.write_text(patched)
    print("Applied fast TestFlight project patch: KittyStore/SideStore stay embedded, while emexDE, CoreCompiler, MobileDevelopmentKit, LiveProcess, and private BuildKit packaging are not built or embedded; TestFlight uses an ASCII app wrapper while preserving the visible display name.")


if __name__ == "__main__":
    main()
