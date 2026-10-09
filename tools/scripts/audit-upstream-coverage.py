#!/usr/bin/env python3
"""Reproducible complete tracked-file parity report for staged native upstreams.

Compares Git index blob IDs, so binary resources and symlinks are included.
Does not modify sources or interpret a changed file as safe to overwrite.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LOCK = json.loads((ROOT / "ThirdParty/upstream-integration.json").read_text())


def tracked(directory, relative_prefix=""):
    raw = subprocess.check_output(["git", "-C", str(directory), "ls-files", "-s", "-z"])
    result = {}
    for item in raw.split(b"\x00"):
        if not item:
            continue
        info, path = item.split(b"\t", 1)
        mode, sha, stage = info.decode("ascii").split()
        if stage != "0":
            raise SystemExit("Unmerged index entry detected: " + path.decode())
        name = path.decode("utf-8", "surrogateescape")
        if name.startswith(relative_prefix):
            result[name[len(relative_prefix):]] = {"mode": mode, "sha": sha}
    return result


def legacy_nyxian_path(name):
    return name[len("Frameworks/"):] if name.startswith("Frameworks/") else name


def compare(local, upstream, translate=lambda path: path):
    mapped = {}
    collisions = []
    for upstream_path, metadata in upstream.items():
        path = translate(upstream_path)
        if path in mapped:
            collisions.append([mapped[path]["upstream_path"], upstream_path])
            continue
        mapped[path] = dict(metadata, upstream_path=upstream_path)

    statuses = {"identical": [], "changed": [], "upstream_only": [], "local_only": [], "type_changed": []}
    for key, upstream_entry in mapped.items():
        old = local.get(key)
        record = {"upstream": upstream_entry["upstream_path"], "local": key,
                  "upstream_sha": upstream_entry["sha"], "upstream_mode": upstream_entry["mode"]}
        if old is None:
            statuses["upstream_only"].append(record)
        else:
            record.update(local_sha=old["sha"], local_mode=old["mode"])
            if old["mode"] != upstream_entry["mode"]:
                statuses["type_changed"].append(record)
            elif old["sha"] == upstream_entry["sha"]:
                statuses["identical"].append(record)
            else:
                statuses["changed"].append(record)
    for key, old in local.items():
        if key not in mapped:
            statuses["local_only"].append({"local": key, "local_sha": old["sha"], "local_mode": old["mode"]})
    statuses["collisions"] = collisions
    summary = {k: len(v) for k, v in statuses.items()}
    summary["upstream_new_areas"] = dict(Counter(
        x["upstream"].split("/")[0] for x in statuses["upstream_only"]
    ).most_common(25))
    summary["modified_areas"] = dict(Counter(
        x["upstream"].split("/")[0] for x in statuses["changed"]
    ).most_common(25))
    return {"summary": summary, "files": statuses}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="build/upstream-coverage.json")
    args = parser.parse_args()

    root_index = tracked(ROOT)
    active_side = {key[len("ThirdParty/SideStore/Source/"):]: value for key, value in root_index.items()
                   if key.startswith("ThirdParty/SideStore/Source/")}
    old_nyx = {key[len("ThirdParty/Nyxian/"):]: value for key, value in root_index.items()
               if key.startswith("ThirdParty/Nyxian/")}

    upstream_side = tracked(ROOT / LOCK["sidestore"]["upstream_path"])
    upstream_nyx = tracked(ROOT / LOCK["nyxian"]["embedded_path"])
    report = {
        "schema": 1,
        "revisions": {"nyxian": LOCK["nyxian"]["revision"], "sidestore": LOCK["sidestore"]["revision"]},
        "sideStore": compare(active_side, upstream_side),
        "nyxianLegacyBuildKit": compare(old_nyx, upstream_nyx, legacy_nyxian_path),
    }
    target = ROOT / args.output
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    for name in ("sideStore", "nyxianLegacyBuildKit"):
        print(f"{name}: {json.dumps(report[name]['summary'], sort_keys=True)}")
    print(f"Full tracked-file report: {target}")


if __name__ == "__main__":
    main()
