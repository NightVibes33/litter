#!/usr/bin/env python3
"""Patch the generated iOS project spec for App Store/TestFlight-safe builds.

Fast TestFlight builds must not link or embed sideloading, provisioning, or
private on-device compiler tooling. The full sideload IPA keeps those targets;
this lane removes them from the generated Xcode project and compiles the app
with LITTER_APP_STORE_SAFE so the matching UI routes are hidden at runtime.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = ROOT / "apps/ios/project.yml"

SIDELOAD_PACKAGES = (
    "AltSign",
    "SemanticVersion",
    "Starscream",
    "KeychainAccess",
    "MarkdownKit",
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

SIDELOAD_TARGETS = (
    "Roxas",
    "AltStoreCore",
    "RustBridge",
    "Minimuxer",
    "SideStore",
)

EMEXDE_TARGETS = (
    "CoreCompiler",
    "MobileDevelopmentKit",
    "emexDE",
    "LiveProcess",
)

DEPENDENCY_BLOCKS = (
    """      - package: AltSign
        product: AltSign-Dynamic
        embed: true
""",
    """      - target: SideStore
        embed: true
""",
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
    "Embed AltSign Dynamic Framework",
    "Embed Upstream Store Sources",
    "Embed emexDE Runtime Resources",
    "Package Private BuildKit Assets",
    "Embed Private BuildKit Frameworks",
)

UNSAFE_TARGETS = SIDELOAD_TARGETS + EMEXDE_TARGETS
UNSAFE_PACKAGES = SIDELOAD_PACKAGES + EMEXDE_PACKAGES


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


def set_app_store_safe_flags(text: str) -> str:
    replacement = (
        '        INFOPLIST_KEY_LitterEmbedsSideStore: "NO"\n'
        '        INFOPLIST_KEY_LitterEmbedsEmexDE: "NO"\n'
        '        OTHER_SWIFT_FLAGS: "$(inherited) -DLITTER_APP_STORE_SAFE"\n'
    )
    text, count = re.subn(
        r'        INFOPLIST_KEY_LitterEmbedsSideStore: ".*"\n'
        r'(?:        INFOPLIST_KEY_LitterEmbedsEmexDE: ".*"\n)?'
        r'(?:        OTHER_SWIFT_FLAGS: "\$\(inherited\) -DLITTER_APP_STORE_SAFE"\n)?',
        replacement,
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit("Fast TestFlight project patch failed: could not set Litter app capability flags")
    return text


def transform(text: str) -> str:
    text = text.replace("        PRODUCT_NAME: Littër\n", "        PRODUCT_NAME: Litter\n")
    text = set_app_store_safe_flags(text)

    for name in UNSAFE_PACKAGES:
        text = remove_named_yaml_section(text, f"  {name}:\n")
    for name in UNSAFE_TARGETS:
        text = remove_named_yaml_section(text, f"  {name}:\n")

    for block in DEPENDENCY_BLOCKS:
        text = text.replace(block, "")

    for name in POST_BUILD_SCRIPT_NAMES:
        text = remove_named_post_build_script(text, name)

    return text


def validate_fast_project(text: str) -> None:
    failures: list[str] = []

    for package in UNSAFE_PACKAGES:
        if f"  {package}:\n" in text:
            failures.append(f"still has unsafe package definition: {package}")
    for target in UNSAFE_TARGETS:
        if f"  {target}:\n" in text:
            failures.append(f"still has unsafe target definition: {target}")

    for block in DEPENDENCY_BLOCKS:
        if block in text:
            failures.append(f"still has Litter dependency block: {block.strip().splitlines()[0].strip()}")

    for name in POST_BUILD_SCRIPT_NAMES:
        if f"      - name: {name}\n" in text:
            failures.append(f"still has post-build script: {name}")

    forbidden_markers = (
        "product: AltSign-Dynamic",
        "target: SideStore",
        "target: CoreCompiler",
        "target: MobileDevelopmentKit",
        "target: emexDE",
        "target: LiveProcess",
        "embed_emexde_corecompiler_artifacts",
        "embed_framework_if_present AltSign-Dynamic",
        "embed_framework_if_present CoreCompiler",
        "copy_upstream_source KittyStore",
        "copy_upstream_source emexDE",
        "../../ThirdParty/SideStore",
        "../../ThirdParty/EmexDE",
    )
    for marker in forbidden_markers:
        if marker in text:
            failures.append(f"still references App-Store-unsafe tooling: {marker}")

    required_markers = (
        '        PRODUCT_NAME: Litter\n',
        '        INFOPLIST_KEY_LitterEmbedsSideStore: "NO"\n',
        '        INFOPLIST_KEY_LitterEmbedsEmexDE: "NO"\n',
        '        OTHER_SWIFT_FLAGS: "$(inherited) -DLITTER_APP_STORE_SAFE"\n',
        "      - target: LitterLiveActivity\n        embed: true\n",
        "      - target: LitterWatch\n        embed: true\n",
    )
    for marker in required_markers:
        if marker not in text:
            failures.append(f"missing required TestFlight-safe marker: {marker.strip()}")

    if re.search(r"^        PRODUCT_NAME: Littër$", text, re.MULTILINE):
        failures.append("still uses non-ASCII iOS PRODUCT_NAME")

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
        print("Fast TestFlight project patch is App Store safe.")
        return

    if patched == original:
        print("Fast TestFlight project patch already applied.")
        return

    PROJECT_YML.write_text(patched)
    print("Applied fast TestFlight project patch: SideStore, AltSign, KittyStore, emexDE, LiveProcess, CoreCompiler, MobileDevelopmentKit, and private BuildKit packaging are removed; runtime feature flags hide those routes.")


if __name__ == "__main__":
    main()
