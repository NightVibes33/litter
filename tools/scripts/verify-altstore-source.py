#!/usr/bin/env python3
"""Validate that the generated AltStore/SideStore source keeps every IPA entry installable."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(?:\.\d+)?$")
ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
SHA256_RE = re.compile(r"^[a-fA-F0-9]{64}$")


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_string(container: dict, key: str, context: str) -> str:
    value = container.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"{context} is missing non-empty string field {key!r}")
    return value.strip()


def require_http_ipa_url(value: str, context: str) -> None:
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        fail(f"{context} has invalid downloadURL {value!r}")
    if not parsed.path.lower().endswith(".ipa"):
        fail(f"{context} downloadURL must point directly at an IPA: {value!r}")
    if "/releases/download/" not in parsed.path:
        fail(f"{context} downloadURL must be a GitHub release asset URL: {value!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Path to litter-altstore-source.json")
    parser.add_argument(
        "--require-news-downloads",
        action="store_true",
        help="Require every app version download URL to also appear as a direct source news item.",
    )
    args = parser.parse_args()

    try:
        source = json.loads(args.source.read_text())
    except Exception as error:
        fail(f"could not read {args.source}: {error}")

    apps = source.get("apps")
    if not isinstance(apps, list) or not apps:
        fail("source must contain at least one app")

    news_urls = set()
    if args.require_news_downloads:
        news = source.get("news")
        if not isinstance(news, list):
            fail("source news must be a list when --require-news-downloads is used")
        for index, item in enumerate(news):
            if not isinstance(item, dict):
                fail(f"news[{index}] must be an object")
            url = item.get("url")
            if isinstance(url, str) and url.strip():
                news_urls.add(url.strip())

    seen_urls: set[str] = set()
    seen_versions: set[tuple[str, str, str]] = set()
    total_versions = 0

    for app_index, app in enumerate(apps):
        if not isinstance(app, dict):
            fail(f"apps[{app_index}] must be an object")
        bundle_id = require_string(app, "bundleIdentifier", f"apps[{app_index}]")
        versions = app.get("versions")
        if not isinstance(versions, list) or not versions:
            fail(f"app {bundle_id} must contain installable versions")

        for version_index, entry in enumerate(versions):
            if not isinstance(entry, dict):
                fail(f"{bundle_id}.versions[{version_index}] must be an object")
            context = f"{bundle_id}.versions[{version_index}]"
            version = require_string(entry, "version", context)
            build = require_string(entry, "buildVersion", context)
            date = require_string(entry, "date", context)
            download_url = require_string(entry, "downloadURL", context)
            sha256 = require_string(entry, "sha256", context)
            require_string(entry, "localizedDescription", context)
            require_string(entry, "minOSVersion", context)

            if not SEMVER_RE.match(version):
                fail(f"{context} has non-SemVer version {version!r}")
            if not ISO_DATE_RE.match(date):
                fail(f"{context} has non-UTC ISO date {date!r}")
            if not SHA256_RE.match(sha256):
                fail(f"{context} has invalid sha256 {sha256!r}")
            require_http_ipa_url(download_url, context)

            size = entry.get("size")
            if not isinstance(size, int) or size <= 0:
                fail(f"{context} must include positive integer size")

            if download_url in seen_urls:
                fail(f"duplicate version downloadURL: {download_url}")
            seen_urls.add(download_url)

            version_key = (bundle_id, version, build)
            if version_key in seen_versions:
                fail(f"duplicate app version/build entry: {bundle_id} {version} ({build})")
            seen_versions.add(version_key)

            if args.require_news_downloads and download_url not in news_urls:
                fail(f"{context} downloadURL is missing from source news: {download_url}")

            total_versions += 1

    print(f"AltStore source verifier passed: {total_versions} installable IPA version(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
