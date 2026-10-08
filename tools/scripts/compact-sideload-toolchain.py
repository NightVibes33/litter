#!/usr/bin/env python3
"""Restore byte-identical Clang command aliases as relative symlinks."""
import argparse
import copy
import hashlib
import pathlib
import shutil
import stat
import zipfile

ALIASES = ('clang++', 'clang-cpp', 'clang-21')


def digest(stream):
    value = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        value.update(chunk)
    return value.digest()


def compact_app(app):
    directory = app / 'Shared/SwiftToolchain/usr/bin'
    canonical = directory / 'clang'
    if not canonical.is_file():
        return
    with canonical.open('rb') as source:
        expected = digest(source)
    saved = 0
    for name in ALIASES:
        alias = directory / name
        if alias.is_symlink() or not alias.is_file():
            continue
        with alias.open('rb') as source:
            if digest(source) != expected:
                raise ValueError(f'{name} differs from clang; refusing to replace it')
        saved += alias.stat().st_size
        alias.unlink()
        alias.symlink_to('clang')
    print(f'Restored Clang aliases; saved {saved} expanded bytes.')


def compact_ipa(source, destination):
    if source.resolve() == destination.resolve():
        raise ValueError('Input and output IPA must differ')
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, 'w', allowZip64=True) as output:
        candidates = [e for e in original.infolist() if e.filename.endswith('.app/Shared/SwiftToolchain/usr/bin/clang')]
        if len(candidates) != 1:
            raise ValueError('Expected exactly one bundled Clang executable')
        canonical = candidates[0]
        with original.open(canonical) as reader:
            expected = digest(reader)
        aliases = {}
        for name in ALIASES:
            path = canonical.filename.rsplit('/', 1)[0] + '/' + name
            entry = original.getinfo(path)
            if stat.S_ISLNK(entry.external_attr >> 16):
                continue
            with original.open(entry) as reader:
                if digest(reader) != expected:
                    raise ValueError(f'{name} differs from clang')
            aliases[path] = entry
        output.comment = original.comment
        for entry in original.infolist():
            metadata = copy.copy(entry)
            if entry.filename in aliases:
                metadata.create_system = 3
                metadata.external_attr = (stat.S_IFLNK | 0o777) << 16
                metadata.compress_type = zipfile.ZIP_STORED
                output.writestr(metadata, b'clang')
            else:
                with original.open(entry) as reader, output.open(metadata, 'w', force_zip64=entry.file_size >= 2**31) as writer:
                    shutil.copyfileobj(reader, writer, 1024 * 1024)
        print(f'Restored {len(aliases)} Clang aliases; saved {sum(e.file_size - 5 for e in aliases.values())} expanded bytes.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--app', type=pathlib.Path)
    group.add_argument('--ipa', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    if args.app:
        compact_app(args.app)
    elif not args.output:
        parser.error('--ipa requires --output')
    else:
        compact_ipa(args.ipa, args.output)


if __name__ == '__main__':
    main()
