#!/usr/bin/env python3
import json
import os
from pathlib import Path
from urllib import request

TOKEN = os.environ["GH_TOKEN"]
REPOSITORY = os.environ["GITHUB_REPOSITORY"]
BASE_SHA = os.environ["GITHUB_SHA"]
API = f"https://api.github.com/repos/{REPOSITORY}"


def github(method: str, path: str, payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = request.Request(
        API + path,
        data=data,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {TOKEN}",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    with request.urlopen(req) as response:
        return json.load(response)


base_commit = github("GET", f"/git/commits/{BASE_SHA}")
base_tree = base_commit["tree"]["sha"]

changed_paths = [
    "apps/ios/Sources/Litter/Models/AIProviderModels.swift",
    "apps/ios/Sources/Litter/Models/AIProviderStore.swift",
    "apps/ios/Sources/Litter/Views/HomeComposerView.swift",
    "apps/ios/Sources/Litter/Views/HomeModelChip.swift",
]

tree_entries = []
for path in changed_paths:
    content = Path(path).read_text()
    blob = github(
        "POST",
        "/git/blobs",
        {"content": content, "encoding": "utf-8"},
    )
    tree_entries.append(
        {"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]}
    )

# The one-shot workflow deletes itself in the generated commit so moving the
# protected branch does not launch an endless patch loop.
tree_entries.append(
    {
        "path": ".github/workflows/wire-pocketkernel-local-home-v3.yml",
        "mode": "100644",
        "type": "blob",
        "sha": None,
    }
)

new_tree = github(
    "POST",
    "/git/trees",
    {"base_tree": base_tree, "tree": tree_entries},
)
new_commit = github(
    "POST",
    "/git/commits",
    {
        "message": "feat: route Home composer to Apple Intelligence",
        "tree": new_tree["sha"],
        "parents": [BASE_SHA],
    },
)

commit_sha = new_commit["sha"]
print(f"REMOTE_COMMIT_SHA={commit_sha}")
output = os.environ.get("GITHUB_OUTPUT")
if output:
    with open(output, "a", encoding="utf-8") as handle:
        handle.write(f"commit_sha={commit_sha}\n")
