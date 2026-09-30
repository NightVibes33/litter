#!/usr/bin/env python3
"""Stage only the pinned released compiler and its own support libraries.

Use its matching public C headers, avoiding private LLVM/Swift header overlays.
The generated project overlay is for device CI; it leaves the source project
and simulator compiler build available in normal development checkouts.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile


def macho_details(data):
    if data[:4] != b'\xcf\xfa\xed\xfe':
        raise SystemExit('Expected an arm64 Mach-O compiler binary')
    if struct.unpack_from('<I', data, 4)[0] != 0x0100000C:
        raise SystemExit('Compiler binary is not arm64')
    position=32; dependencies=[]; symbols=set()
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size=struct.unpack_from('<II', data, position)
        if size < 8:
            raise SystemExit('Invalid compiler load command')
        if command in (0xc, 0x80000018, 0x8000001f):
            offset=struct.unpack_from('<I', data, position+8)[0]
            dependencies.append(data[position+offset:position+size].split(b'\0')[0].decode())
        if command == 2:
            offset, count, strings, _=struct.unpack_from('<IIII', data, position+8)
            for index in range(count):
                string_index, kind, section, _, _=struct.unpack_from('<IBBHQ', data, offset+index*16)
                if kind & 1 and section:
                    start=strings+string_index
                    end=data.find(b'\0', start)
                    symbols.add(data[start:end].decode())
        position += size
    return dependencies, symbols


def overlay_project(project):
    text=project.read_text()
    framework='../../build/upstream-corecompiler/CoreCompiler.framework'
    replacement='      - framework: ' + framework
    if replacement in text:
        return
    text, count=re.subn(r'^  CoreCompiler:\n.*?(?=^  HWHook:)', '', text, flags=re.M|re.S)
    if count != 1 or text.count('      - target: CoreCompiler') != 4:
        raise SystemExit('Unexpected compiler target/dependency declarations')
    text=text.replace('      - target: CoreCompiler', replacement)
    before='              "$BUILT_PRODUCTS_DIR/$name.framework" \\\n'
    after='              "$SRCROOT/../../build/upstream-corecompiler/$name.framework" \\\n' + before
    if text.count(before) != 1:
        raise SystemExit('Missing framework embedding candidate list')
    text=text.replace(before, after)
    project.write_text(text)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--stage-only', action='store_true')
    parser.add_argument('--project', type=Path)
    args=parser.parse_args(); root=args.root.resolve()
    record=json.loads((root/'docs/architecture/nyxian-released-compiler.json').read_text())
    output=root/'build/upstream-corecompiler'; output.mkdir(parents=True, exist_ok=True)
    archive=args.archive or output/record['assetName']
    if not archive.exists():
        subprocess.run(['curl', '-fL', '--retry', '3', '--max-time', '300', record['downloadUrl'], '-o', str(archive)], check=True)
    digest=hashlib.sha256()
    with archive.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''):
            digest.update(chunk)
    if archive.stat().st_size != record['assetSize'] or digest.hexdigest() != record['assetSha256']:
        raise SystemExit('Released compiler archive identity mismatch')
    source=root/'ThirdParty/EmexDE/Source'; revision=record['sourceRevision']
    if subprocess.run(['git', '-C', str(source), 'cat-file', '-e', revision+'^{commit}'], capture_output=True).returncode:
        subprocess.run(['git', '-C', str(source), 'fetch', '--depth', '1', 'origin', revision], check=True)
    framework=output/'CoreCompiler.framework'
    if framework.exists():
        shutil.rmtree(framework)
    framework.mkdir()
    prefix=record['frameworkPrefix']
    with zipfile.ZipFile(archive) as bundle:
        for name in bundle.namelist():
            if not name.startswith(prefix) or name.endswith('/'):
                continue
            relative=Path(name[len(prefix):])
            if relative.is_absolute() or '..' in relative.parts:
                raise SystemExit('Unsafe compiler archive path')
            if relative.parts[0] == '_CodeSignature':
                continue
            destination=framework/relative; destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(bundle.read(name))
    spec=importlib.util.spec_from_file_location('deployment', root/'tools/scripts/verify-unicorn-deployment.py')
    deployment=importlib.util.module_from_spec(spec); spec.loader.exec_module(deployment)
    support=framework/'Frameworks'
    libraries=sorted(support.glob('lib_Compiler*.dylib'))
    if len(libraries) != record['supportLibraryCount']:
        raise SystemExit('Released compiler support library closure changed')
    available={path.name for path in libraries}
    binary=framework/'CoreCompiler'; symbols=set()
    checksums={}
    for path in [binary, *libraries]:
        data=path.read_bytes(); versions=list(deployment.versions(data))
        if not versions or any(platform != 2 or version > 18 << 16 for platform,version in versions):
            raise SystemExit('Released compiler dependency requires a newer OS: '+path.name)
        dependencies, exports=macho_details(data)
        if path == binary:
            symbols=exports
        for dependency in dependencies:
            if dependency.startswith('/usr/lib/') or dependency.startswith('/System/'):
                continue
            if not dependency.startswith('@rpath/') or Path(dependency).name not in available:
                raise SystemExit('Unresolved compiler dependency: '+dependency)
        checksums[path.name]=hashlib.sha256(data).hexdigest()
    if '_CCSwiftCompilerJobExecute' not in symbols:
        raise SystemExit('Released framework lacks the Swift frontend entry point')
    # Public C headers are unchanged except for an additional CCMachO API in the
    # release. Copy the exact release headers; private compiler headers stay out.
    listing=subprocess.check_output(['git', '-C', str(source), 'ls-tree', '-r', '--name-only', revision, '--', 'Frameworks/CoreCompiler'], text=True).splitlines()
    headers=framework/'Headers'; headers.mkdir()
    for name in listing:
        if not name.endswith('.h') or Path(name).name.endswith('Private.h'):
            continue
        data=subprocess.check_output(['git', '-C', str(source), 'show', revision+':'+name])
        if b'#include <llvm/' in data or b'#include <swift/' in data or b'#include <clang/' in data:
            raise SystemExit('Private compiler header in public interface: '+name)
        current=source/name
        if current.exists():
            compatible=data.replace(b'#include <CoreCompiler/CCMachO.h>\n', b'')
            if compatible != current.read_bytes():
                raise SystemExit('Released public compiler API differs from retained source: '+name)
        functions=re.findall(rb'CC_EXPORT\s+[^;]*?\b(CC\w+)\s*\(', data)
        missing=[function.decode() for function in functions if '_'+function.decode() not in symbols]
        if missing:
            raise SystemExit('Released compiler lacks public API exports: '+', '.join(missing))
        (headers/Path(name).name).write_bytes(data)
    modules=framework/'Modules'; modules.mkdir()
    (modules/'module.modulemap').write_text('framework module CoreCompiler {\n  umbrella header "CoreCompiler.h"\n  export *\n  module * { export * }\n}\n')
    # Existing app embedding/signing expects support dylibs at app Frameworks
    # level. Keep all of them from this release and preserve their binary bytes.
    destination=source/'Frameworks/CoreCompiler/CoreCompilerSupportLibs'
    destination.mkdir(exist_ok=True)
    for stale in destination.glob('lib_Compiler*.dylib'):
        stale.unlink()
    for library in libraries:
        shutil.copyfile(library, destination/library.name)
    shutil.rmtree(support)
    (output/'PROVENANCE.json').write_text(json.dumps({'release':record, 'binarySha256':checksums}, indent=2)+'\n')
    if not args.stage_only:
        overlay_project(args.project or root/'apps/ios/project.yml')
    print('Staged pinned CoreCompiler and 13 matching support libraries; iOS deployment and dynamic closure verified')


if __name__ == '__main__':
    main()
