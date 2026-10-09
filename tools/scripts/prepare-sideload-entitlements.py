#!/usr/bin/env python3
"""Attach discoverable V8 entitlement metadata before a sideload signer takes over."""
import argparse
import plistlib
import shutil
from pathlib import Path
import subprocess
import tempfile

VA = "com.apple.developer.kernel.extended-virtual-addressing"


def prepare(app: Path) -> None:
    info = plistlib.loads((app / "Info.plist").read_bytes())
    name = info.get("CFBundleExecutable")
    if not isinstance(name, str) or not name or Path(name).name != name:
        raise ValueError("Invalid CFBundleExecutable")
    executable = app / name
    if not executable.is_file() or executable.is_symlink():
        raise ValueError("Missing app executable or unexpected symlink")
    with tempfile.TemporaryDirectory(prefix="alleycat-entitlements-") as directory:
        entitlements = Path(directory) / "entitlements.plist"
        entitlements.write_bytes(plistlib.dumps({VA: True}))
        # codesign recognizes a bundle's main executable even when given its
        # file path and creates _CodeSignature. Sign a detached copy instead.
        detached_executable = Path(directory) / name
        shutil.copy2(executable, detached_executable)
        # AltSign reads entitlement requests from this Mach-O signature.
        subprocess.run([
            "/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none",
            "--entitlements", str(entitlements), "--generate-entitlement-der",
            str(detached_executable),
        ], check=True)
        shutil.copy2(detached_executable, executable)
    result = subprocess.run([
        "/usr/bin/codesign", "-d", "--entitlements", ":-", str(executable),
    ], check=True, capture_output=True)
    if plistlib.loads(result.stdout).get(VA) is not True:
        raise ValueError("Sideload executable lost required extended virtual addressing")
    if (app / "embedded.mobileprovision").exists() or (app / "_CodeSignature").exists():
        raise ValueError("Sideload payload unexpectedly contains a team profile or resource seal")
    print("Sideload executable requests extended virtual addressing; final signer/profile must grant it.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    prepare(parser.parse_args().app)
