#!/usr/bin/env python3
"""Check the recorded runtime dependency closure without changing any revisions."""

from pathlib import Path
import argparse
import json
import re
import subprocess
import sys
import tomllib


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def verify(root):
    errors = []
    checked = 0

    def require(path):
        nonlocal checked
        checked += 1
        if not path.exists() or (path.is_file() and path.stat().st_size == 0):
            errors.append(f"missing or empty dependency: {path.relative_to(root)}")

    def submodules(repo):
        # Read gitlinks, not .gitmodules: upstream can retain obsolete entries.
        for line in git(repo, "ls-tree", "-r", "HEAD").splitlines():
            entry, name = line.split("\t", 1)
            mode, _, revision = entry.split()
            if mode != "160000":
                continue
            path = repo / name
            require(path / ".git")
            if not (path / ".git").exists():
                continue
            actual = git(path, "rev-parse", "HEAD")
            if actual != revision:
                errors.append(f"wrong revision: {path.relative_to(root)}: {actual}, expected {revision}")
            submodules(path)

    submodules(root)

    native_lock = root / "ThirdParty/SideStore/NATIVE_DEPENDENCIES.json"
    native_helper = root / "ThirdParty/SideStore/native-dependencies.rs"
    require(native_lock)
    require(native_helper)
    if native_lock.is_file() and native_helper.is_file():
        helper_source = native_helper.read_text()
        for name, dependency in json.loads(native_lock.read_text())["dependencies"].items():
            revision = dependency["commit"]
            if not re.fullmatch(r"[0-9a-f]{40}", revision):
                errors.append(f"invalid native dependency revision: {name}")
                continue
            pattern = (r'\(\s*"' + re.escape(dependency["repository"]) +
                       r'"\s*,\s*"' + revision + r'"\s*,?\s*\)')
            if not re.search(pattern, helper_source):
                errors.append(f"native build helper does not match the dependency lock: {name}")
            source = root / "ThirdParty/SideStore/NativeDependencies" / name
            require(source / ".git")
            require(source / "autogen.sh")
            if (source / ".git").exists() and git(source, "rev-parse", "HEAD") != revision:
                errors.append(f"native source does not match the dependency lock: {name}")

    for name in ("SideStore", "Feather", "Nyxian"):
        source = root / "ThirdParty" / name
        if name != "Nyxian":
            source /= "Source"
        inventory = source / ".litter-submodules.txt"
        require(inventory)
        if not inventory.is_file():
            continue
        for line in inventory.read_text().splitlines():
            match = re.fullmatch(r" ([0-9a-f]{40}) (\S+)(?: \(.*\))?", line)
            if not match:
                errors.append(f"invalid snapshot submodule record: {inventory.relative_to(root)}: {line}")
                continue
            require(source / match[2])
            # A directory alone is not a populated source snapshot.
            if not any(p.is_file() for p in (source / match[2]).rglob("*")):
                errors.append(f"empty snapshot submodule: {name}/{match[2]}")

    # Check every committed file in the source snapshots, including nested
    # dependencies. Git object availability does not establish checkout readiness.
    for line in git(root, "ls-files", "ThirdParty").splitlines():
        path = root / line
        if path.is_symlink():
            if not path.exists():
                errors.append(f"broken dependency symlink: {line}")
        elif not path.exists():
            errors.append(f"missing source snapshot file: {line}")

    for relative in (
        "ThirdParty/SideStore/minimuxer/Cargo.toml",
        "ThirdParty/SideStore/Source/Dependencies/minimuxer/RustBridge/Cargo.toml",
        "shared/rust-bridge/Cargo.toml",
    ):
        manifest = root / relative
        require(manifest)
        require(manifest.with_name("Cargo.lock"))
        if not manifest.is_file():
            continue
        data = tomllib.loads(manifest.read_text())
        tables = [data.get("dependencies", {}), data.get("build-dependencies", {}), data.get("dev-dependencies", {}),
                  data.get("workspace", {}).get("dependencies", {})]
        tables.extend(data.get("patch", {}).values())
        for table in tables:
            for dependency in table.values():
                if isinstance(dependency, dict) and "path" in dependency:
                    require((manifest.parent / dependency["path"] / "Cargo.toml").resolve())

    for relative in (
        "apps/ios/Litter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        "ThirdParty/EmexDE/Source/Nyxian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        "ThirdParty/SideStore/Source/Dependencies/minimuxer/Package.resolved",
        "ThirdParty/SideStore/SideSign/Package.resolved",
    ):
        lock = root / relative
        require(lock)
        if lock.is_file():
            for pin in json.loads(lock.read_text()).get("pins", []):
                if not re.fullmatch(r"[0-9a-f]{40}", pin.get("state", {}).get("revision", "")):
                    errors.append(f"missing Swift package revision: {relative}: {pin.get('identity')}")

    sidesign = root / "ThirdParty/SideStore/SideSign"
    for relative in ("Package.swift", "LITTER_IMPORT.json", ".litter-upstream-commit", "Sources/CodeSigning/CodeSignerAPI.swift"):
        require(sidesign / relative)
    if (sidesign / "LITTER_IMPORT.json").is_file():
        manifest = json.loads((sidesign / "LITTER_IMPORT.json").read_text())
        if (sidesign / ".litter-upstream-commit").read_text().strip() != manifest["commit"]:
            errors.append("SideSign source revision does not match its import manifest")
        package = (sidesign / "Package.swift").read_text()
        resolved = json.loads((sidesign / "Package.resolved").read_text())["pins"]
        if resolved != manifest["dependencies"]:
            errors.append("SideSign resolved dependency graph differs from its import manifest")
        for pin in manifest["dependencies"]:
            state = pin["state"]
            requirement = state.get("version") or state["revision"]
            kind = "exact" if "version" in state else "revision"
            pattern = r'\.package\(url:\s*"' + re.escape(pin["location"]) + r'",\s*' + kind + r':\s*"' + re.escape(requirement) + r'"'
            if not re.search(pattern, package) and pin["identity"] != "swift-asn1":
                errors.append(f"SideSign dependency requirement is not pinned: {pin['identity']}")
        if re.search(r"^\s*\.package\(.*branch:", package, re.MULTILINE):
            errors.append("SideSign has a moving branch dependency")

    return checked, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    checked, errors = verify(args.root.resolve())
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"Recorded upstream dependency sources verified ({checked} required paths).")
    print("This source check does not validate downloaded native binaries, SDKs, or device behavior.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
