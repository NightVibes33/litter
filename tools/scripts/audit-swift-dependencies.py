#!/usr/bin/env python3
"""Inventory tracked Swift pins against OSV; local source patches need review."""
import argparse
import json
import subprocess
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
files = subprocess.check_output(
    ['git', 'ls-files', '*Package.resolved'], cwd=root, text=True
).splitlines()
commits = {}
for name in files:
    data = json.loads((root / name).read_text())
    for pin in data.get('pins', data.get('object', {}).get('pins', [])):
        state = pin.get('state', {})
        revision = state.get('revision')
        if revision:
            commits.setdefault(revision, []).append({
                'file': name, 'identity': pin.get('identity', pin.get('package')),
                'version': state.get('version'),
            })
findings = []
keys = sorted(commits)
for offset in range(0, len(keys), 100):
    batch = keys[offset:offset + 100]
    request = urllib.request.Request(
        'https://api.osv.dev/v1/querybatch',
        data=json.dumps({'queries': [{'commit': key} for key in batch]}).encode(),
        headers={'Content-Type': 'application/json'}, method='POST',
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        results = json.load(response)['results']
    if len(results) != len(batch):
        raise RuntimeError('OSV returned an incomplete batch')
    for revision, result in zip(batch, results):
        if result.get('error'):
            raise RuntimeError(str(result['error']))
        for advisory in result.get('vulns', []):
            findings.append({'revision': revision, 'advisory': advisory['id'],
                             'occurrences': commits[revision]})
report = {
    'lockfiles': files, 'unique_commits': len(keys), 'findings': findings,
    'packages_requiring_source_review': [{
        'path': 'ThirdParty/Feather/Source/Zip',
        'reason': 'Local Zip 2.1.2 extraction-boundary source patch; see LITTER_PATCHES.md',
    }],
}
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(f'{len(files)} Swift resolutions, {len(keys)} commits: {len(findings)} OSV matches')
raise SystemExit(bool(findings))
