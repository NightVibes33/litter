#!/usr/bin/env python3
"""Patch the generated iOS project spec for App Store/TestFlight-safe builds.

Fast TestFlight builds must not link or embed sideloading, provisioning, or
private on-device compiler tooling. The full sideload IPA keeps those targets;
this lane removes them from the generated Xcode project and compiles the app
with LITTER_APP_STORE_SAFE so the matching UI routes are hidden at runtime.
It also omits the embedded Watch app from TestFlight builds so Apple processing
does not fail on Watch-specific icon metadata while the iOS app is being tested.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = ROOT / "apps/ios/project.yml"
INFO_PLIST = ROOT / "apps/ios/Sources/Litter/Info.plist"

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
    """      - path: Sources/Litter/Resources/TipJarProducts.storekit
""",
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
    """      - target: LitterWatch
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

PROJECT_LINE_REPLACEMENTS = (
    (
        '        INFOPLIST_KEY_UIBackgroundModes: "audio fetch remote-notification picture-in-picture"\n',
        '',
    ),
    (
        '    attributes:\n      SystemCapabilities:\n        com.apple.BackgroundModes:\n          enabled: true\n',
        '',
    ),
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


def remove_plist_key_block(text: str, key: str) -> str:
    pattern = re.compile(
        rf"\t<key>{re.escape(key)}</key>\n"
        rf"\t(?P<value><(?:array|dict)>.*?\n\t</(?:array|dict)>|<(?:true|false)/>|<string>.*?</string>)\n",
        re.DOTALL,
    )
    return pattern.sub("", text)


def strip_info_plist_app_store_sensitive_keys(text: str) -> str:
    for block in (
        """	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>com.sigkitten.litter.turn-check</string>
	</array>
""",
        """	<key>NSSupportsLiveActivities</key>
	<true/>
	<key>NSSupportsLiveActivitiesFrequentUpdates</key>
	<true/>
""",
        """	<key>UIFileSharingEnabled</key>
	<true/>
	<key>LSSupportsOpeningDocumentsInPlace</key>
	<true/>
""",
        """	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
		<string>fetch</string>
		<string>remote-notification</string>
	</array>
""",
    ):
        text = text.replace(block, "")

    for key in (
        "LSApplicationQueriesSchemes",
        "UTImportedTypeDeclarations",
    ):
        text = remove_plist_key_block(text, key)

    return text



def transform(text: str) -> str:
    for before, after in PROJECT_LINE_REPLACEMENTS:
        text = text.replace(before, after)
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
        '        PRODUCT_NAME: "Alley Cat"\n',
        '        INFOPLIST_KEY_LitterEmbedsSideStore: "NO"\n',
        '        INFOPLIST_KEY_LitterEmbedsEmexDE: "NO"\n',
        '        OTHER_SWIFT_FLAGS: "$(inherited) -DLITTER_APP_STORE_SAFE"\n',
        "      - target: LitterLiveActivity\n        embed: true\n",
    )
    for marker in required_markers:
        if marker not in text:
            failures.append(f"missing required TestFlight-safe marker: {marker.strip()}")

    if re.search(r'^        PRODUCT_NAME: Littër$', text, re.MULTILINE):
        failures.append("still uses non-ASCII iOS PRODUCT_NAME")


    if '        INFOPLIST_KEY_UIBackgroundModes: "audio fetch remote-notification picture-in-picture"\n' in text:
        failures.append("still enables background modes on the TestFlight-safe app target")
    if '    attributes:\n      SystemCapabilities:\n        com.apple.BackgroundModes:\n          enabled: true\n' in text:
        failures.append("still enables background modes capability on the TestFlight-safe app target")

    if failures:
        raise SystemExit("Fast TestFlight project patch failed:\n- " + "\n- ".join(failures))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate the transformed output without writing")
    args = parser.parse_args()

    original = PROJECT_YML.read_text()
    patched = transform(original)
    validate_fast_project(patched)

    info_original = INFO_PLIST.read_text()
    info_patched = strip_info_plist_app_store_sensitive_keys(info_original)

    info_failures = []
    for marker in (
        "com.sigkitten.litter.ipa",
        "com.rsa.pkcs-12",
        "com.apple.mobileprovision",
        "com.apple.mobiledevicepairing",
        "sidestore",
        "altstore",
        "kittystore",
        "localdevvpn",
    ):
        if marker in info_patched:
            info_failures.append(f"still has TestFlight-sensitive Info.plist marker: {marker}")
    if info_failures:
        raise SystemExit("Fast TestFlight Info.plist patch failed:\n- " + "\n- ".join(info_failures))

    if args.check:
        print("Fast TestFlight project patch is App Store safe.")
        return

    if patched == original and info_patched == info_original:
        print("Fast TestFlight project patch already applied.")
        return

    PROJECT_YML.write_text(patched)
    if info_patched != info_original:
        INFO_PLIST.write_text(info_patched)
    print("Applied fast TestFlight project patch: SideStore, AltSign, KittyStore, emexDE, LiveProcess, CoreCompiler, MobileDevelopmentKit, embedded Watch app, background modes, file sharing, document-in-place support, IPA/signing document types, sideload URL schemes, and private BuildKit packaging are removed; runtime feature flags hide those routes.")


if __name__ == "__main__":
    main()
