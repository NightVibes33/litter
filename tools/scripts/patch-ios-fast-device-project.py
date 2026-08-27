#!/usr/bin/env python3
"""Patch the generated iOS project spec for fast unsigned device builds.

The fast unsigned IPA still needs KittyStore/SideStore for sideload testing, but
it should not build the hidden emexDE/BuildKit toolchain targets. Keep this
separate from the TestFlight patch, which also removes SideStore and AltSign.

This patch wires the exact forcequitOS/bad_query source into Litter's existing
readFile/writeFile/listDirectory actions. The bad_query source lives under
apps/ios/UnsignedOnly and is added to the Litter target only by this unsigned
build patch. TestFlight never runs this script and its separate preflight rejects
all UnsignedOnly/BadQuery references.
"""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = ROOT / "apps/ios/project.yml"
APPLE_AGENT = ROOT / "apps/ios/Sources/Litter/Models/AppleOnDeviceAgent.swift"
APPLE_BRIDGE = ROOT / "apps/ios/Sources/Litter/Views/AppleLocalAgentBridge.swift"
BRIDGING_HEADER = ROOT / "apps/ios/Sources/Litter/Bridge/codex_bridge_objc.h"
BAD_QUERY_C = ROOT / "apps/ios/UnsignedOnly/BadQuery/bad_query.c"
BAD_QUERY_H = ROOT / "apps/ios/UnsignedOnly/BadQuery/bad_query.h"
DEVICE_ROUTE_ACCESS = ROOT / "apps/ios/UnsignedOnly/BadQuery/DeviceRouteAccess.swift"

UNSIGNED_BAD_QUERY_SOURCE = "      - path: UnsignedOnly/BadQuery\n"
UNSIGNED_BAD_QUERY_HEADER = '#import "../../../UnsignedOnly/BadQuery/bad_query.h"\n'
UPSTREAM_BAD_QUERY_C_BLOB = "dce2c4db47152efd4f84826c99e4348016126416"
UPSTREAM_BAD_QUERY_H_BLOB = "4b79ce65ecfd3ed44055d1b1d10b4f24b801d258"

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


def add_unsigned_bad_query_source(text: str) -> str:
    if UNSIGNED_BAD_QUERY_SOURCE in text:
        return text
    marker = "    sources:\n      - path: Sources/Litter\n"
    if marker not in text:
        raise SystemExit("Fast unsigned device project patch failed: could not locate Litter source list")
    return text.replace(marker, marker + UNSIGNED_BAD_QUERY_SOURCE, 1)


def transform(text: str) -> str:
    text = set_fast_device_flags(text)
    text = add_unsigned_bad_query_source(text)
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


def transform_apple_agent(text: str) -> str:
    guidance_marker = "            Prefer a plain answer when execution is unnecessary.\n"
    guidance = (
        guidance_marker
        + "            In this unsigned build, readFile/writeFile/listDirectory can also target the iOS device routes exposed by bad_query when the user supplies an absolute supported path.\n"
        + "            Keep using those same three filesystem actions; the runtime selects iSH or bad_query from the path.\n"
    )
    if "the runtime selects iSH or bad_query from the path" not in text:
        if guidance_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple agent guidance marker missing")
        text = text.replace(guidance_marker, guidance, 1)
    return text


def transform_apple_bridge(text: str) -> str:
    read_marker = """            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            let text = try await IshFS.readTextFile(path: path, maxBytes: 256_000)
            return "\\(path)\\n\\n\\(limited(text))"
"""
    read_replacement = """            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            if DeviceRouteAccess.shouldHandle(path) {
                let text = try DeviceRouteAccess.readText(path: path, maxBytes: 256_000)
                return "\\(path)\\n\\n\\(limited(text))"
            }
            let text = try await IshFS.readTextFile(path: path, maxBytes: 256_000)
            return "\\(path)\\n\\n\\(limited(text))"
"""
    if "DeviceRouteAccess.readText(path: path" not in text:
        if read_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple bridge readFile marker missing")
        text = text.replace(read_marker, read_replacement, 1)

    write_marker = """            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            try await IshFS.writeTextFile(path: path, text: content)
            return "Wrote \\(content.utf8.count) bytes to \\(path)."
"""
    write_replacement = """            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            if DeviceRouteAccess.shouldHandle(path) {
                let bytes = try DeviceRouteAccess.writeText(path: path, text: content)
                return "Wrote \\(bytes) bytes to \\(path)."
            }
            try await IshFS.writeTextFile(path: path, text: content)
            return "Wrote \\(content.utf8.count) bytes to \\(path)."
"""
    if "DeviceRouteAccess.writeText(path: path" not in text:
        if write_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple bridge writeFile marker missing")
        text = text.replace(write_marker, write_replacement, 1)

    list_marker = """            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            let command = "LC_ALL=C ls -la -- \\(IshFS.shellQuote(path))"
"""
    list_replacement = """            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            if DeviceRouteAccess.shouldHandle(path) {
                let body = try DeviceRouteAccess.listDirectory(path: path)
                return "\\(path)\\n\\n\\(limited(body))"
            }
            let command = "LC_ALL=C ls -la -- \\(IshFS.shellQuote(path))"
"""
    if "DeviceRouteAccess.listDirectory(path: path)" not in text:
        if list_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple bridge listDirectory marker missing")
        text = text.replace(list_marker, list_replacement, 1)

    transcript_marker = """        case .listDirectory:
            let path = Self.resolvedPath(
                proposal.path ?? "",
                workDirectory: workDirectory
            )
            store.appendCommand(
                turnID: localTurnID,
                command: "LC_ALL=C ls -la -- \\(IshFS.shellQuote(path))",
                cwd: workDirectory,
                output: result,
                exitCode: 0
            )
"""
    transcript_replacement = """        case .listDirectory:
            let path = Self.resolvedPath(
                proposal.path ?? "",
                workDirectory: workDirectory
            )
            if DeviceRouteAccess.shouldHandle(path) {
                store.appendNote(
                    turnID: localTurnID,
                    title: "List \\(path)",
                    body: result
                )
            } else {
                store.appendCommand(
                    turnID: localTurnID,
                    command: "LC_ALL=C ls -la -- \\(IshFS.shellQuote(path))",
                    cwd: workDirectory,
                    output: result,
                    exitCode: 0
                )
            }
"""
    if "title: \"List \\(path)\"" not in text:
        if transcript_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple bridge list transcript marker missing")
        text = text.replace(transcript_marker, transcript_replacement, 1)

    return text


def transform_bridging_header(text: str) -> str:
    if UNSIGNED_BAD_QUERY_HEADER in text:
        return text
    if not text.endswith("\n"):
        text += "\n"
    return text + UNSIGNED_BAD_QUERY_HEADER


def git_blob_sha(path: Path) -> str:
    data = path.read_bytes()
    header = f"blob {len(data)}\0".encode()
    return hashlib.sha1(header + data).hexdigest()


def validate_exact_upstream_bad_query() -> list[str]:
    failures: list[str] = []
    expected = (
        (BAD_QUERY_C, UPSTREAM_BAD_QUERY_C_BLOB),
        (BAD_QUERY_H, UPSTREAM_BAD_QUERY_H_BLOB),
    )
    for path, blob_sha in expected:
        if not path.is_file():
            failures.append(f"missing unsigned bad_query source: {path.relative_to(ROOT)}")
            continue
        actual = git_blob_sha(path)
        if actual != blob_sha:
            failures.append(
                f"{path.relative_to(ROOT)} is not byte-for-byte upstream: expected Git blob {blob_sha}, got {actual}"
            )
    return failures


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
        UNSIGNED_BAD_QUERY_SOURCE,
    )
    for marker in required_kept:
        if marker not in text:
            failures.append(f"removed unsigned sideload dependency unexpectedly: {marker.strip()}")

    if failures:
        raise SystemExit("Fast unsigned device project patch failed:\n- " + "\n- ".join(failures))


def validate_bad_query_agent(agent: str, bridge: str, header: str) -> None:
    failures = validate_exact_upstream_bad_query()

    invented_actions = (
        "readDeviceFile",
        "writeDeviceFile",
        "listDeviceDirectory",
    )
    for marker in invented_actions:
        if marker in agent or marker in bridge:
            failures.append(f"invented device action is still present: {marker}")

    for marker in (
        "action must be one of: answer, runCommand, readFile, writeFile, listDirectory.",
        "the runtime selects iSH or bad_query from the path",
    ):
        if marker not in agent:
            failures.append(f"Apple agent missing marker: {marker}")

    for marker in (
        "DeviceRouteAccess.shouldHandle(path)",
        "DeviceRouteAccess.readText(path: path",
        "DeviceRouteAccess.writeText(path: path",
        "DeviceRouteAccess.listDirectory(path: path)",
    ):
        if marker not in bridge:
            failures.append(f"Apple bridge missing marker: {marker}")

    if UNSIGNED_BAD_QUERY_HEADER not in header:
        failures.append("bridging header does not import unsigned bad_query.h")

    if not DEVICE_ROUTE_ACCESS.is_file():
        failures.append(f"missing unsigned route glue: {DEVICE_ROUTE_ACCESS.relative_to(ROOT)}")
    else:
        route_glue = DEVICE_ROUTE_ACCESS.read_text()
        for marker in (
            "bad_query(pathBuffer.baseAddress",
            "bad_query_list(buffer.baseAddress",
            "bad_query_release(handle)",
            "static func shouldHandle",
        ):
            if marker not in route_glue:
                failures.append(f"DeviceRouteAccess missing marker: {marker}")

    if failures:
        raise SystemExit("Fast unsigned bad_query agent patch failed:\n- " + "\n- ".join(failures))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate the transformed output without writing")
    args = parser.parse_args()

    original_project = PROJECT_YML.read_text()
    original_agent = APPLE_AGENT.read_text()
    original_bridge = APPLE_BRIDGE.read_text()
    original_header = BRIDGING_HEADER.read_text()

    patched_project = transform(original_project)
    patched_agent = transform_apple_agent(original_agent)
    patched_bridge = transform_apple_bridge(original_bridge)
    patched_header = transform_bridging_header(original_header)

    validate_fast_device_project(patched_project)
    validate_bad_query_agent(patched_agent, patched_bridge, patched_header)

    if args.check:
        print("Fast unsigned device project + exact bad_query read/list/write integration is valid.")
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

    if not changed:
        print("Fast unsigned device project + exact bad_query integration already applied.")
        return

    print(
        "Applied fast unsigned device patch: KittyStore remains embedded, emexDE/private BuildKit are excluded, "
        "and the existing Apple-agent readFile/writeFile/listDirectory actions route supported iOS paths through "
        "byte-for-byte upstream forcequitOS/bad_query. The bad_query source is injected only into this unsigned target."
    )


if __name__ == "__main__":
    main()
