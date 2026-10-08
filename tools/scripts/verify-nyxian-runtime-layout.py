#!/usr/bin/env python3
"""Reject CI-only toolchains in Nyxian runtime payloads."""
import argparse
from pathlib import Path
import zipfile


def verify(app):
    if list(app.rglob('SwiftToolchain')):
        raise ValueError('Standalone SwiftToolchain must not be embedded')
    for name in ('include', 'lib', 'swift'):
        archive = app / 'Shared' / (name + '.zip')
        if not archive.is_file() or not zipfile.is_zipfile(archive):
            raise ValueError('Missing upstream compressed resource: ' + name)
    if not (app / 'Frameworks/CoreCompiler.framework/CoreCompiler').is_file():
        raise ValueError('Missing in-process CoreCompiler framework')
    print('Nyxian runtime layout verified: framework and compressed resources; no standalone toolchain.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    verify(parser.parse_args().app)
