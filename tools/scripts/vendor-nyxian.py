#!/usr/bin/env python3
"""Stage and validate a recursive, pinned Nyxian source import before replacing it."""

import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).rstrip("\n")


def main():
    repository = os.environ.get("NYXIAN_REPO", "https://github.com/ProjectNyxian/Nyxian.git")
    revision = os.environ.get("NYXIAN_COMMIT", "d955607acf4e8112c28d1db01837fc3e11631de3")
    destination = Path(os.environ.get("NYXIAN_DEST", str(ROOT / "ThirdParty/Nyxian"))).resolve()
    if destination == ROOT or ROOT.is_relative_to(destination):
        raise SystemExit("error: source destination cannot replace the repository or its parents")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".nyxian-import-", dir=destination.parent) as temp:
        temp = Path(temp)
        checkout = temp / "checkout"
        staged = temp / "staged"
        subprocess.run(["git", "clone", "--no-checkout", "--depth", "1", repository, str(checkout)], check=True)
        git(checkout, "fetch", "--depth", "1", "origin", revision)
        git(checkout, "checkout", "--detach", "FETCH_HEAD")
        actual = git(checkout, "rev-parse", "HEAD")
        if actual != revision:
            raise SystemExit("error: NYXIAN_COMMIT must be an exact full commit SHA")
        overlay_path = destination / "LITTER_LOCAL_OVERLAYS.json"
        overlays = json.loads(overlay_path.read_text()) if overlay_path.exists() else {"paths": []}
        if overlays.get("paths") and overlays.get("baseCommit") != actual:
            raise SystemExit("error: rebase the recorded Litter compiler compatibility overlays before changing NYXIAN_COMMIT")
        git(checkout, "submodule", "update", "--init", "--recursive")
        records = git(checkout, "submodule", "status", "--recursive").splitlines()
        if any(not line.startswith(" ") for line in records):
            raise SystemExit("error: a Nyxian dependency is missing or at the wrong revision")

        openssl = "Nyxian/LindChain/OpenSSL.xcframework"
        excluded_suffixes = (".ipa", ".mobileprovision", ".p12", ".cer")

        def ignore(directory, names):
            relative = Path(directory).relative_to(checkout).as_posix()
            ignored = []
            for name in names:
                if name in (".git", "_CodeSignature") or name.endswith(excluded_suffixes):
                    ignored.append(name)
                elif name.endswith((".framework", ".xcframework")) and not (
                    f"{relative}/{name}" == openssl or relative.startswith(openssl + "/")
                ):
                    ignored.append(name)
                elif relative == openssl and name not in ("Info.plist", "ios-arm64"):
                    ignored.append(name)
            return ignored

        shutil.copytree(checkout, staged, symlinks=True, ignore=ignore)
        info = staged / openssl / "Info.plist"
        if info.exists():
            metadata = plistlib.loads(info.read_bytes())
            metadata["AvailableLibraries"] = [
                library for library in metadata.get("AvailableLibraries", [])
                if library.get("LibraryIdentifier") == "ios-arm64"
            ]
            info.write_bytes(plistlib.dumps(metadata))
        local_bridge = destination / "LitterBuildKitNative"
        if not local_bridge.is_dir():
            raise SystemExit("error: existing LitterBuildKitNative bridge must be present; import aborted")
        shutil.copytree(local_bridge, staged / "LitterBuildKitNative", dirs_exist_ok=True)
        for relative in overlays["paths"]:
            source = destination / relative
            target = staged / relative
            if not source.is_file() or not source.resolve().is_relative_to(destination):
                raise SystemExit(f"error: missing or unsafe Litter compatibility overlay: {relative}")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        if overlay_path.exists():
            shutil.copy2(overlay_path, staged / overlay_path.name)
        (staged / ".litter-submodules.txt").write_text("\n".join(records) + "\n")
        manifest = {
            "repository": repository,
            "commit": actual,
            "preservedLocalPaths": ["LitterBuildKitNative", *overlays["paths"]],
            "excludedFromVendorArchive": [".git", "*.framework (except OpenSSL ios-arm64)",
                                          "*.xcframework (except OpenSSL ios-arm64)", *excluded_suffixes],
            "submoduleStatusFile": ".litter-submodules.txt",
            "vendoringMode": "recursive-pinned-source-import",
        }
        (staged / "LITTER_NYXIAN_IMPORT.json").write_text(json.dumps(manifest, indent=2) + "\n")
        # Keep the old focused toolchain record explicitly historical. The
        # current source import and its recursive dependencies use this manifest.
        old_lock = destination / "VENDOR_LOCK.json"
        if old_lock.exists():
            historical = json.loads(old_lock.read_text())
            historical["supersededBy"] = "LITTER_NYXIAN_IMPORT.json"
            historical["notes"] = "Historical focused import; current revisions are in LITTER_NYXIAN_IMPORT.json and .litter-submodules.txt."
            (staged / "VENDOR_LOCK.json").write_text(json.dumps(historical, indent=2) + "\n")
        environment = dict(os.environ, NYXIAN_ROOT=str(staged))
        subprocess.run(["sh", str(ROOT / "tools/scripts/verify-nyxian-source-import.sh")],
                       env=environment, check=True)
        backup = temp / "previous"
        destination.rename(backup)
        try:
            staged.rename(destination)
        except BaseException:
            backup.rename(destination)
            raise
        print(f"Imported Nyxian {actual} with {len(records)} pinned recursive dependencies.")


if __name__ == "__main__":
    main()
