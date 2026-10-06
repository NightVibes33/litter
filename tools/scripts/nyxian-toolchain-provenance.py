#!/usr/bin/env python3
"""Verify complete upstream toolchain artifacts against the pinned source graph."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[2]
NYXIAN = REPO / 'ThirdParty/EmexDE/Source'
LLVM = NYXIAN / 'LLVM-On-iOS'
FILES = ('compiler-support.tar.gz', 'SwiftToolchain.zip')


def git_sha(path):
    return subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()


def expected_sources():
    branch = next(line.split('?=', 1)[1].strip() for line in (LLVM / 'Makefile').read_text().splitlines() if line.startswith('SWIFT_BRANCH ?='))
    return {'nyxian_revision': git_sha(NYXIAN), 'llvm_on_ios_revision': git_sha(LLVM), 'swift_tag': branch}


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def verify(directory, expected):
    manifest = json.loads((directory / 'provenance.json').read_text())
    if manifest.get('schema') != 1 or manifest.get('sources') != expected:
        raise ValueError('Toolchain provenance does not match the pinned Nyxian/LLVM/Swift revisions')
    for name in FILES:
        if not (directory / name).is_file() or digest(directory / name) != manifest.get('sha256', {}).get(name):
            raise ValueError(f'Toolchain artifact checksum mismatch: {name}')
    for name in ('swift', 'llvm-project'):
        if not manifest.get('built_revisions', {}).get(name):
            raise ValueError(f'Missing upstream build revision: {name}')
    return manifest


def main():
    command, directory = sys.argv[1], Path(sys.argv[2])
    expected = expected_sources()
    if command == 'create':
        manifest = {'schema': 1, 'sources': expected,
                    'built_revisions': {name: git_sha(LLVM / name) for name in ('swift', 'llvm-project')},
                    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
                    'sha256': {name: digest(directory / name) for name in FILES}}
        (directory / 'provenance.json').write_text(json.dumps(manifest, indent=2) + '\n')
    elif command == 'verify':
        verify(directory, expected)
        print('Pinned upstream toolchain provenance and artifact checksums verified')
    else:
        raise ValueError(f'Unknown command: {command}')


if __name__ == '__main__':
    main()
