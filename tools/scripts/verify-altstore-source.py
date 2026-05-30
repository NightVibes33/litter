#!/usr/bin/env python3
"""Validate that the generated KittyStore/AltStore source keeps every IPA entry installable."""
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


def require_https_image_url(value: str, context: str) -> None:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        fail(f"{context} has invalid screenshot URL {value!r}")
    if not parsed.path.lower().endswith((".png", ".jpg", ".jpeg", ".heic", ".webp")):
        fail(f"{context} screenshot URL must point directly at an image: {value!r}")


def validate_screenshot_collection(items: object, context: str) -> int:
    if not isinstance(items, list) or not items:
        fail(f"{context} must be a non-empty screenshot list")

    count = 0
    for index, item in enumerate(items):
        item_context = f"{context}[{index}]"
        if isinstance(item, str):
            require_https_image_url(item.strip(), item_context)
        elif isinstance(item, dict):
            image_url = require_string(item, "imageURL", item_context)
            require_https_image_url(image_url, item_context)
            for dimension in ("width", "height"):
                value = item.get(dimension)
                if not isinstance(value, int) or value <= 0:
                    fail(f"{item_context} must include positive integer {dimension!r}")
        else:
            fail(f"{item_context} must be a screenshot URL string or object")
        count += 1
    return count


def require_app_screenshots(app: dict, context: str) -> None:
    count = 0

    if "screenshotURLs" in app:
        count += validate_screenshot_collection(app.get("screenshotURLs"), f"{context}.screenshotURLs")

    if "screenshots" in app:
        screenshots = app.get("screenshots")
        if isinstance(screenshots, list):
            count += validate_screenshot_collection(screenshots, f"{context}.screenshots")
        elif isinstance(screenshots, dict):
            found_device_collection = False
            for device in ("iphone", "ipad"):
                if device in screenshots:
                    found_device_collection = True
                    count += validate_screenshot_collection(screenshots.get(device), f"{context}.screenshots.{device}")
            if not found_device_collection:
                fail(f"{context}.screenshots must include iphone or ipad screenshots")
        else:
            fail(f"{context}.screenshots must be an object or list")

    if count == 0:
        fail(f"{context} must include app screenshots")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Path to litter-altstore-source.json")
    parser.add_argument(
        "--require-news-downloads",
        action="store_true",
        help="Require every app version download URL to also appear as a direct source news item.",
    )
    parser.add_argument(
        "--require-screenshots",
        action="store_true",
        help="Require every app entry to include screenshotURLs or screenshots metadata.",
    )
    parser.add_argument(
        "--max-news-items",
        type=int,
        default=None,
        help="Fail if source news contains more than this many items.",
    )
    args = parser.parse_args()

    try:
        source = json.loads(args.source.read_text())
    except Exception as error:
        fail(f"could not read {args.source}: {error}")

    apps = source.get("apps")
    if not isinstance(apps, list) or not apps:
        fail("source must contain at least one app")

    news = source.get("news", [])
    if args.require_news_downloads or args.max_news_items is not None:
        if not isinstance(news, list):
            fail("source news must be a list")
        if args.max_news_items is not None and len(news) > args.max_news_items:
            fail(f"source news has {len(news)} item(s), expected at most {args.max_news_items}")

    news_urls = set()
    if args.require_news_downloads:
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
        app_context = f"apps[{app_index}]"
        bundle_id = require_string(app, "bundleIdentifier", app_context)
        if args.require_screenshots:
            require_app_screenshots(app, app_context)
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
