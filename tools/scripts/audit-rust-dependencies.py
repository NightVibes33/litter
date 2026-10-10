#!/usr/bin/env python3
"""Query OSV for every registry dependency in tracked Cargo lockfiles.

Local/path dependencies need source review, including the atty compatibility
adapter. Findings are not dismissed or suppressed. This does not replace the
repository's private GitHub Dependabot alert list.
"""

import argparse
from collections import defaultdict
import json
from pathlib import Path
import subprocess
import tomllib
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip())
    files = subprocess.check_output(
        ["git", "ls-files", "*Cargo.lock"], cwd=root, text=True
    ).splitlines()
    packages = defaultdict(list)
    source_packages = defaultdict(list)
    for filename in files:
        with (root / filename).open("rb") as handle:
            lock = tomllib.load(handle)
        for package in lock["package"]:
            if package.get("source", "").startswith("registry+"):
                packages[package["name"], package["version"]].append(filename)
            else:
                source_packages[package["name"], package["version"], package.get("source", "local/path")].append(filename)

    versions = sorted(packages)
    findings = []
    for start in range(0, len(versions), 250):
        batch = versions[start:start + 250]
        payload = {"queries": [
            {"package": {"ecosystem": "crates.io", "name": name}, "version": version}
            for name, version in batch
        ]}
        request = urllib.request.Request(
            "https://api.osv.dev/v1/querybatch",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            results = json.load(response)["results"]
        if len(results) != len(batch):
            raise RuntimeError("Incomplete OSV response")
        for (name, version), result in zip(batch, results):
            if result.get("vulns"):
                findings.append({
                    "name": name, "version": version,
                    "lockfiles": packages[name, version],
                    "advisories": result["vulns"],
                })
    report = {
        "lockfiles": files, "registry_versions_checked": len(versions),
        "findings": findings,
        "packages_requiring_source_review": [
            {"name": name, "version": version, "source": source, "lockfiles": lockfiles}
            for (name, version, source), lockfiles in sorted(source_packages.items())
        ],
        "limitation": "Registry advisories only; local patches require source review. Counts are not GitHub alert counts.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Checked {len(versions)} registry versions across {len(files)} lockfiles.")
    print(f"{len(findings)} versions have advisories; report: {args.output}")


if __name__ == "__main__":
    main()
