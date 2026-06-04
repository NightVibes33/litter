#!/usr/bin/env python3
"""Patch the generated iOS project spec for fast unsigned device builds.

The fast unsigned IPA still needs KittyStore/SideStore for sideload testing, but
it should not build the hidden emexDE/BuildKit toolchain targets. Keep this
separate from the TestFlight patch, which also removes SideStore and AltSign.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = ROOT / "apps/ios/project.yml"

EMEXDE_TARGETS = (
    "CoreCompiler",
    "MobileDevelopmentKit",
    "emexDE",
    "LiveProcess",
)

EMEXDE_PACKAGES = (
    "EmexDERunestone",
    "EmexDESwiftTerm",
    "EmexDETreeSitterObjc",
    "EmexDETreeSitterC",
    "EmexDETreeSitterCPP",
    "EmexDETreeSitterXML",
    "EmexDETreeSitterSwift",
    "EmexDEUIOnboarding",
)

EMEXDE_DEPENDENCY_BLOCKS = (
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


def set_fast_device_flags(text: str) -> str:
    replacement = (
        '        INFOPLIST_KEY_LitterEmbedsSideStore: "YES"\n'
        '        INFOPLIST_KEY_LitterEmbedsEmexDE: "NO"\n'
    )
    text, count = re.subn(
        r'        INFOPLIST_KEY_LitterEmbedsSideStore: ".*"\n'
        r'(?:        INFOPLIST_KEY_LitterEmbedsEmexDE: ".*"\n)?',
        replacement,
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit("Fast unsigned device project patch failed: could not set Litter app capability flags")
    return text


def transform(text: str) -> str:
    text = set_fast_device_flags(text)
    for name in EMEXDE_TARGETS + EMEXDE_PACKAGES:
        text = remove_named_yaml_section(text, f"  {name}:\n")

    for block in EMEXDE_DEPENDENCY_BLOCKS:
        text = text.replace(block, "")

    text = text.replace("          embed_emexde_corecompiler_artifacts\n", "")
    text = text.replace("          embed_framework_if_present CoreCompiler 1\n", "")
    text = text.replace("          copy_upstream_source emexDE \"$SRCROOT/../../ThirdParty/EmexDE/Source\"\n", "")

    for name in POST_BUILD_SCRIPT_NAMES:
        text = remove_named_post_build_script(text, name)

    return text


def validate_fast_device_project(text: str) -> None:
    failures: list[str] = []

    for target in EMEXDE_TARGETS:
        if f"  {target}:\n" in text:
            failures.append(f"still has emexDE target definition: {target}")

    for package in EMEXDE_PACKAGES:
        if f"  {package}:\n" in text:
            failures.append(f"still has emexDE package definition: {package}")

    for block in EMEXDE_DEPENDENCY_BLOCKS:
        if block in text:
            failures.append(f"still has Litter dependency block: {block.strip().splitlines()[0].strip()}")

    for name in POST_BUILD_SCRIPT_NAMES:
        if f"      - name: {name}\n" in text:
            failures.append(f"still has post-build script: {name}")

    if re.search(r"^          embed_emexde_corecompiler_artifacts$", text, re.MULTILINE):
        failures.append("still calls embed_emexde_corecompiler_artifacts")
    if re.search(r"^          embed_framework_if_present CoreCompiler 1$", text, re.MULTILINE):
        failures.append("still requires CoreCompiler.framework embedding")
    if "copy_upstream_source emexDE" in text:
        failures.append("still copies emexDE upstream source")

    required_kept = (
        "        INFOPLIST_KEY_LitterEmbedsSideStore: \"YES\"\n",
        "        INFOPLIST_KEY_LitterEmbedsEmexDE: \"NO\"\n",
        "  SideStore:\n",
        "  AltStoreCore:\n",
        "  Roxas:\n",
        "  Minimuxer:\n",
        "  RustBridge:\n",
        "      - target: SideStore\n        embed: true\n",
        "        product: AltSign-Dynamic\n",
    )
    for marker in required_kept:
        if marker not in text:
            failures.append(f"removed unsigned sideload dependency unexpectedly: {marker.strip()}")

    if failures:
        raise SystemExit("Fast unsigned device project patch failed:\n- " + "\n- ".join(failures))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate the transformed output without writing")
    args = parser.parse_args()

    original = PROJECT_YML.read_text()
    patched = transform(original)
    validate_fast_device_project(patched)

    if args.check:
        print("Fast unsigned device project patch is valid.")
        return

    if patched == original:
        print("Fast unsigned device project patch already applied.")
        return

    PROJECT_YML.write_text(patched)
    print("Applied fast unsigned device project patch: KittyStore/SideStore remain embedded and visible, while emexDE, CoreCompiler, MobileDevelopmentKit, LiveProcess, and private BuildKit packaging are not built or embedded.")


if __name__ == "__main__":
    main()
