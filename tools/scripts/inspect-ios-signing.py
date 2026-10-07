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
    print('Apple filtered bundle-ID lookup: ' + json.dumps({
        'requestedIdentifier': identifier,
        'returnedCount': len(bundles),
        'returnedIdentifiers': [b.get('attributes', {}).get('identifier') for b in bundles],
    }))
    # Apple's identifier filter also returns extension/prefix matches.
    bundles = [b for b in bundles if b['attributes']['identifier'] == identifier]
    if not bundles:
        # Match the signing lane's paginated bundle-ID list when Apple's filtered
        # endpoint returns no resources for an otherwise registered identifier.
        listed = apple.collection('/v1/bundleIds?limit=200')
        bundles = [b for b in listed if b['attributes']['identifier'] == identifier]
        print(f'Apple bundle lookup: filtered=0, listed={len(listed)}, exact_matches={len(bundles)}')
    if len(bundles) != 1 or bundles[0]['attributes']['identifier'] != identifier:
        raise RuntimeError('Expected exactly one matching Apple bundle ID')
    bundle = bundles[0]
    capabilities = apple.collection(f"/v1/bundleIds/{bundle['id']}/bundleIdCapabilities")
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
