#!/usr/bin/env python3
"""Check actual object deployment targets, including universal static archives."""
import pathlib, plistlib, struct, sys

def versions(data):
    if data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = data[:4] == b'\xca\xfe\xba\xbf'
        for n in range(struct.unpack_from('>I', data, 4)[0]):
            pos = 8 + n * (32 if wide else 20)
            offset, size = struct.unpack_from('>QQ' if wide else '>II', data, pos + 8)
            yield from versions(data[offset:offset + size])
    elif data.startswith(b'!<arch>\n'):
        pos = 8
        while pos + 60 <= len(data):
            header = data[pos:pos + 60]; size = int(header[48:58]); member = data[pos + 60:pos + 60 + size]
            if header[:16].startswith(b'#1/'):
                member = member[int(header[:16].split(b'/')[1].strip()):]
            yield from versions(member)
            pos += 60 + size + (size % 2)
    elif data[:4] == b'\xcf\xfa\xed\xfe':
        pos = 32
        for _ in range(struct.unpack_from('<I', data, 16)[0]):
            command, size = struct.unpack_from('<II', data, pos)
            if size < 8: raise ValueError('invalid Mach-O command')
            if command == 0x32:
                yield struct.unpack_from('<II', data, pos + 8)
            elif command in (0x24, 0x25):
                # Older x86 iOS objects use LC_VERSION_MIN_IPHONEOS for simulators.
                cpu = struct.unpack_from('<I', data, 4)[0]
                platform = 1 if command == 0x24 else (7 if cpu == 0x01000007 else 2)
                yield (platform, struct.unpack_from('<I', data, pos + 8)[0])
            pos += size

def main():
    root = pathlib.Path(sys.argv[1])
    info = plistlib.loads((root / 'Info.plist').read_bytes())
    seen = set()
    for library in info['AvailableLibraries']:
        platform = library['SupportedPlatform']; variant = library.get('SupportedPlatformVariant', '')
        key = (platform, variant)
        if platform not in ('macos', 'ios'): continue
        seen.add(key)
        expected, maximum = {( 'macos', ''): (1, 12 << 16), ('ios', ''): (2, 18 << 16), ('ios', 'simulator'): (7, 18 << 16)}[key]
        found = list(versions((root / library['LibraryIdentifier'] / library['LibraryPath']).read_bytes()))
        if not found: raise SystemExit(f'No deployment metadata: {key}')
        for actual, minimum in found:
            if actual != expected or minimum > maximum:
                raise SystemExit(f'Incompatible native object: {key}, platform={actual}, minimum={minimum >> 16}.{(minimum >> 8) & 255}.{minimum & 255}')
    required = {('ios', ''), ('ios', 'simulator')} if '--ios-only' in sys.argv else {('macos', ''), ('ios', ''), ('ios', 'simulator')}
    if seen != required:
        raise SystemExit(f'Missing native slices: {seen}')
    print(f'{root.name} object deployment targets support iOS 18' + (' and macOS 12' if ('macos', '') in required else ''))


if __name__ == "__main__":
    main()
