#!/usr/bin/env python3
"""Apply the ARMv7 libxev alignment fix in the renderer's isolated Zig cache."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def patch_completion(path: Path) -> None:
    original = 'const c: *Completion = @fieldParentPtr("task", t);'
    fixed = 'const c: *Completion = @alignCast(@fieldParentPtr("task", t));'
    source = path.read_text()
    if fixed in source:
        return
    if source.count(original) != 1:
        raise ValueError(f"libxev completion callback changed: {path}")
    # t points to a field of an already-aligned Completion allocation. Recovering
    # its parent preserves that alignment; Task's pointer type alone loses it.
    path.write_text(source.replace(original, fixed))


def main() -> None:
    ghostty = Path(sys.argv[1])
    zig = sys.argv[2]
    cache = Path(os.environ['ZIG_GLOBAL_CACHE_DIR'])
    zon = (ghostty / 'build.zig.zon').read_text()
    dependency = re.search(r'\.libxev\s*=\s*\.\{(.*?)\n\s*\},', zon, re.S)
    if dependency is None:
        raise ValueError('Ghostty libxev dependency declaration changed')
    url = re.search(r'\.url\s*=\s*"([^"]+)"', dependency[1])[1]
    expected_hash = re.search(r'\.hash\s*=\s*"([^"]+)"', dependency[1])[1]
    with tempfile.TemporaryDirectory() as download_dir:
        archive = Path(download_dir) / 'libxev.tar.gz'
        subprocess.run(['curl', '-fsSL', '--retry', '3', '-o', str(archive), url], check=True)
        actual_hash = subprocess.check_output([zig, 'fetch', str(archive)], text=True).strip()
    if actual_hash != expected_hash:
        raise ValueError('libxev download does not match Ghostty dependency hash')
    patch_completion(cache / 'p' / expected_hash / 'src/backend/epoll.zig')
    print('Applied libxev parent-pointer alignment fix for ARMv7')


if __name__ == '__main__':
    main()
