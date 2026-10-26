"""Recognize reviewed fork changes only while both source blobs still match."""


def classify_drift(protected, upstream, fork, reviewed):
    drift = []
    accepted = []
    for path in sorted(protected):
        if path in upstream and upstream[path] == fork.get(path):
            continue
        entry = reviewed.get(path, {})
        if (
            path in upstream
            and path in fork
            and entry.get("upstream_blob") == upstream[path]
            and entry.get("fork_blob") == fork[path]
            and entry.get("reason", "").strip()
        ):
            accepted.append(path)
        else:
            drift.append(path)
    return drift, accepted
