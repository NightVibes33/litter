#!/usr/bin/env python3
"""Read the exact iOS App ID capabilities without creating signing assets."""
import argparse
import importlib.util
import json
from pathlib import Path
import urllib.parse


def inspect(apple, identifier):
    query = urllib.parse.urlencode({'filter[identifier]': identifier})
    bundles = apple.collection('/v1/bundleIds?' + query)
    if len(bundles) != 1 or bundles[0]['attributes']['identifier'] != identifier:
        raise RuntimeError('Expected exactly one matching Apple bundle ID')
    bundle = bundles[0]
    capabilities = apple.collection(f"/v1/bundleIds/{bundle['id']}/bundleIdCapabilities?limit=200")
    result = {
        'identifier': identifier,
        'platform': bundle['attributes'].get('platform'),
        'capabilityTypes': sorted(c['attributes']['capabilityType'] for c in capabilities),
    }
    print('Apple registered App ID capabilities: ' + json.dumps(result, sort_keys=True))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle-id', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('distribution', Path(__file__).with_name('testflight-distribution.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    inspect(module.Apple(), args.bundle_id)
