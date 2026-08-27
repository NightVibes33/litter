#!/usr/bin/env python3
"""Patch the generated iOS project spec for fast unsigned device builds.

The fast unsigned IPA still needs KittyStore/SideStore for sideload testing, but
it should not build the hidden emexDE/BuildKit toolchain targets. Keep this
separate from the TestFlight patch, which also removes SideStore and AltSign.

This patch also wires the forcequitOS/bad_query research route into the Apple
on-device agent. The bad_query source lives under apps/ios/UnsignedOnly and is
added to the Litter target only by this unsigned-build patch. TestFlight never
runs this script, so the sandbox-route implementation is not compiled into the
TestFlight target.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = ROOT / "apps/ios/project.yml"
APPLE_AGENT = ROOT / "apps/ios/Sources/Litter/Models/AppleOnDeviceAgent.swift"
APPLE_BRIDGE = ROOT / "apps/ios/Sources/Litter/Views/AppleLocalAgentBridge.swift"
BRIDGING_HEADER = ROOT / "apps/ios/Sources/Litter/Bridge/codex_bridge_objc.h"

UNSIGNED_BAD_QUERY_SOURCE = "      - path: UnsignedOnly/BadQuery\n"
UNSIGNED_BAD_QUERY_HEADER = '#import "../../../UnsignedOnly/BadQuery/bad_query.h"\n'

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
    if "case readDeviceFile" not in text:
        text = text.replace(
            "        case listDirectory\n",
            "        case listDirectory\n        case readDeviceFile\n        case writeDeviceFile\n        case listDeviceDirectory\n",
            1,
        )

    text = text.replace(
        "            action must be one of: answer, runCommand, readFile, writeFile, listDirectory.\n",
        "            action must be one of: answer, runCommand, readFile, writeFile, listDirectory, readDeviceFile, writeDeviceFile, listDeviceDirectory.\n",
        1,
    )

    guidance_marker = "            Prefer a plain answer when execution is unnecessary.\n"
    guidance = (
        guidance_marker
        + "            readFile/writeFile/listDirectory operate inside Litter's iSH/Linux filesystem.\n"
        + "            readDeviceFile/writeDeviceFile/listDeviceDirectory operate on the iOS host filesystem and require an absolute path beginning with /.\n"
        + "            Use a device action for paths such as /var/mobile, /var/containers, /private/var, or /System.\n"
    )
    if "readDeviceFile/writeDeviceFile/listDeviceDirectory operate on the iOS host filesystem" not in text:
        if guidance_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple agent guidance marker missing")
        text = text.replace(guidance_marker, guidance, 1)

    text = text.replace(
        "        case .readFile, .writeFile, .listDirectory:\n",
        "        case .readFile, .writeFile, .listDirectory, .readDeviceFile, .writeDeviceFile, .listDeviceDirectory:\n",
        1,
    )

    absolute_guard_marker = "            proposal.path = path\n            proposal.command = nil\n            proposal.requiresApproval = true\n\n"
    absolute_guard = (
        "            proposal.path = path\n"
        "            proposal.command = nil\n"
        "            proposal.requiresApproval = true\n\n"
        "            let isDeviceAction = proposal.action == .readDeviceFile\n"
        "                || proposal.action == .writeDeviceFile\n"
        "                || proposal.action == .listDeviceDirectory\n"
        "            if isDeviceAction && !path.hasPrefix(\"/\") {\n"
        "                throw AppleOnDeviceAgentError.actionRejected(\"Device filesystem actions require an absolute iOS path.\")\n"
        "            }\n\n"
    )
    if "let isDeviceAction = proposal.action == .readDeviceFile" not in text:
        if absolute_guard_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple agent path validation marker missing")
        text = text.replace(absolute_guard_marker, absolute_guard, 1)

    text = text.replace(
        "            if proposal.action == .writeFile {\n",
        "            if proposal.action == .writeFile || proposal.action == .writeDeviceFile {\n",
        1,
    )
    return text


def transform_apple_bridge(text: str) -> str:
    if "case .readDeviceFile:" not in text:
        record_marker = """        case .listDirectory:
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
        }
    }
"""
        record_replacement = """        case .listDirectory:
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

        case .readDeviceFile:
            let path = proposal.path ?? ""
            store.appendNote(
                turnID: localTurnID,
                title: "Read device \\(path)",
                body: result
            )

        case .writeDeviceFile:
            let path = proposal.path ?? ""
            store.appendFileChange(
                turnID: localTurnID,
                path: path,
                content: proposal.content ?? "",
                summary: result
            )

        case .listDeviceDirectory:
            let path = proposal.path ?? ""
            store.appendNote(
                turnID: localTurnID,
                title: "Listed device \\(path)",
                body: result
            )
        }
    }
"""
        if record_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple bridge transcript switch marker missing")
        text = text.replace(record_marker, record_replacement, 1)

        execute_marker = """        case .listDirectory:
            guard let rawPath = proposal.path else {
                throw bridgeError("The approved directory path is missing.")
            }
            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            let command = "LC_ALL=C ls -la -- \\(IshFS.shellQuote(path))"
            let result = await IshFS.run(command, cwd: workDirectory)
            guard result.exitCode == 0 else {
                throw runtimeError(
                    label: "Directory listing",
                    exitCode: result.exitCode,
                    output: result.output
                )
            }
            let body = result.output.isEmpty ? "(empty directory)" : limited(result.output)
            return "\\(path)\\n\\n\\(body)"
        }
    }
"""
        execute_replacement = """        case .listDirectory:
            guard let rawPath = proposal.path else {
                throw bridgeError("The approved directory path is missing.")
            }
            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            let command = "LC_ALL=C ls -la -- \\(IshFS.shellQuote(path))"
            let result = await IshFS.run(command, cwd: workDirectory)
            guard result.exitCode == 0 else {
                throw runtimeError(
                    label: "Directory listing",
                    exitCode: result.exitCode,
                    output: result.output
                )
            }
            let body = result.output.isEmpty ? "(empty directory)" : limited(result.output)
            return "\\(path)\\n\\n\\(body)"

        case .readDeviceFile:
            guard let path = proposal.path else {
                throw bridgeError("The approved device file path is missing.")
            }
            let text = try DeviceRouteAccess.readText(path: path, maxBytes: 256_000)
            return "\\(path)\\n\\n\\(limited(text))"

        case .writeDeviceFile:
            guard let path = proposal.path,
                  let content = proposal.content else {
                throw bridgeError("The approved device file write is incomplete.")
            }
            let bytes = try DeviceRouteAccess.writeText(path: path, text: content)
            return "Wrote \\(bytes) bytes to device route \\(path)."

        case .listDeviceDirectory:
            guard let path = proposal.path else {
                throw bridgeError("The approved device directory path is missing.")
            }
            let body = try DeviceRouteAccess.listDirectory(path: path)
            return "\\(path)\\n\\n\\(limited(body))"
        }
    }
"""
        if execute_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: Apple bridge execution switch marker missing")
        text = text.replace(execute_marker, execute_replacement, 1)

        display_marker = """        case .answer: return "Answer"
        case .runCommand: return "Run Command"
        case .readFile: return "Read File"
        case .writeFile: return "Write File"
        case .listDirectory: return "List Directory"
"""
        display_replacement = display_marker + """        case .readDeviceFile: return "Read Device File"
        case .writeDeviceFile: return "Write Device File"
        case .listDeviceDirectory: return "List Device Directory"
"""
        if display_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: action display-name switch marker missing")
        text = text.replace(display_marker, display_replacement, 1)

        icon_marker = """        case .answer: return "text.bubble.fill"
        case .runCommand: return "terminal.fill"
        case .readFile: return "doc.text.fill"
        case .writeFile: return "square.and.pencil"
        case .listDirectory: return "folder.fill"
"""
        icon_replacement = icon_marker + """        case .readDeviceFile: return "iphone.and.arrow.forward"
        case .writeDeviceFile: return "iphone.and.arrow.forward"
        case .listDeviceDirectory: return "iphone.gen3"
"""
        if icon_marker not in text:
            raise SystemExit("Fast unsigned device patch failed: action icon switch marker missing")
        text = text.replace(icon_marker, icon_replacement, 1)

    text = text.replace(
        "Using Litter's existing local iSH runtime.",
        "Using Litter's approved local runtime.",
    )
    return text


def transform_bridging_header(text: str) -> str:
    if UNSIGNED_BAD_QUERY_HEADER in text:
        return text
    if not text.endswith("\n"):
        text += "\n"
    return text + UNSIGNED_BAD_QUERY_HEADER


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
    failures: list[str] = []
    for marker in (
        "case readDeviceFile",
        "case writeDeviceFile",
        "case listDeviceDirectory",
        "readDeviceFile/writeDeviceFile/listDeviceDirectory operate on the iOS host filesystem",
        "proposal.action == .writeFile || proposal.action == .writeDeviceFile",
    ):
        if marker not in agent:
            failures.append(f"Apple agent missing marker: {marker}")

    for marker in (
        "case .readDeviceFile:",
        "case .writeDeviceFile:",
        "case .listDeviceDirectory:",
        "DeviceRouteAccess.readText",
        "DeviceRouteAccess.writeText",
        "DeviceRouteAccess.listDirectory",
    ):
        if marker not in bridge:
            failures.append(f"Apple bridge missing marker: {marker}")

    if UNSIGNED_BAD_QUERY_HEADER not in header:
        failures.append("bridging header does not import unsigned bad_query.h")

    for path in (
        ROOT / "apps/ios/UnsignedOnly/BadQuery/bad_query.c",
        ROOT / "apps/ios/UnsignedOnly/BadQuery/bad_query.h",
        ROOT / "apps/ios/UnsignedOnly/BadQuery/DeviceRouteAccess.swift",
    ):
        if not path.is_file():
            failures.append(f"missing unsigned bad_query source: {path.relative_to(ROOT)}")

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
        print("Fast unsigned device project + bad_query agent patch is valid.")
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
        print("Fast unsigned device project + bad_query agent patch already applied.")
        return

    print(
        "Applied fast unsigned device patch: KittyStore remains embedded, emexDE/private BuildKit are excluded, "
        "and the Apple on-device agent gains approval-gated iOS device-route read/list/write via bad_query. "
        "The bad_query source is injected only into this unsigned build target."
    )


if __name__ == "__main__":
    main()
