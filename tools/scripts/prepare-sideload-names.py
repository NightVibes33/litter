#!/usr/bin/env python3
"""Use ASCII bundle names for sideloaders that pass them to Apple's appIdName."""
import argparse
import copy
import pathlib
import plistlib
import re
import shutil
import unicodedata
import zipfile


def prepare(data):
    info = plistlib.loads(data)
    before = dict(info)
    for key in ('CFBundleName', 'CFBundleDisplayName'):
        if key in info:
            value = unicodedata.normalize('NFKD', info[key]).encode('ascii', 'ignore').decode()
            value = re.sub(r'[^A-Za-z0-9 -]', ' ', value)
            value = ' '.join(value.split())[:50].strip()
            if not value:
                raise ValueError(f'{key} has no usable ASCII name')
            info[key] = value
    if info == before:
        return data
    fmt = plistlib.FMT_BINARY if data.startswith(b'bplist') else plistlib.FMT_XML
    return plistlib.dumps(info, fmt=fmt, sort_keys=False)


def repackage(source, destination):
    if source.resolve() == destination.resolve():
        raise ValueError('Input and output IPA must differ')
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, 'w', allowZip64=True) as output:
        output.comment = original.comment
        for entry in original.infolist():
            metadata = copy.copy(entry)
            if re.fullmatch(r'Payload/[^/]+\.app/(?:.*\.(?:app|appex)/)?Info\.plist', entry.filename):
                output.writestr(metadata, prepare(original.read(entry)))
            else:
                with original.open(entry) as reader, output.open(metadata, 'w', force_zip64=entry.file_size >= 2**31) as writer:
                    shutil.copyfileobj(reader, writer, 1024 * 1024)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--app', type=pathlib.Path)
    group.add_argument('--ipa', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    if args.app:
        paths = [args.app / 'Info.plist']
        paths += [path / 'Info.plist' for path in args.app.rglob('*') if path.is_dir() and path.suffix in ('.app', '.appex')]
        for path in paths:
            path.write_bytes(prepare(path.read_bytes()))
        print(f'Prepared ASCII sideload names in {len(paths)} bundle(s).')
    else:
        if not args.output:
            parser.error('--ipa requires --output')
        repackage(args.ipa, args.output)
        print('Repackaged unsigned IPA with ASCII sideload names.')


if __name__ == '__main__':
    main()
