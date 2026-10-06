import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]


class NativeFrameworkLinkTests(unittest.TestCase):
    def test_existing_mdk_is_linked_without_compiling_duplicate_classes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / 'tools/scripts'
            scripts.mkdir(parents=True)
            bins = root / 'bin'
            bins.mkdir()
            log = root / 'compiler.jsonl'
            compiler = bins / 'compiler'
            compiler.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
with open(os.environ['COMPILER_LOG'], 'a') as output:
    output.write(json.dumps(sys.argv[1:]) + '\\n')
args = sys.argv[1:]
pathlib.Path(args[args.index('-o') + 1]).write_bytes(b'fixture binary')
''')
            (bins / 'uname').write_text('#!/bin/sh\nprintf "Darwin\\n"\n')
            (bins / 'xcrun').write_text(f'#!/bin/sh\nprintf "%s\\n" "{compiler}"\n')
            (bins / 'lipo').write_text('#!/bin/sh\nexit 0\n')
            for tool in bins.iterdir():
                tool.chmod(0o755)
            script = scripts / 'build-litter-buildkit-native.sh'
            script.write_text((REPO / 'tools/scripts/build-litter-buildkit-native.sh').read_text()
                              .replace('/usr/bin/lipo', str(bins / 'lipo')))
            source = root / 'ThirdParty/Nyxian/LitterBuildKitNative'
            source.mkdir(parents=True)
            for name in ['LitterBuildKitNative.h', 'LitterBuildKitNative.mm', 'LitterBuildKitInProcess.mm']:
                (source / name).write_text('// fixture source\n')
            frameworks = root / 'Frameworks'
            for name in ['CoreCompiler', 'MobileDevelopmentKit']:
                headers = frameworks / name
                headers.mkdir(parents=True)
                (headers / f'{name}.h').write_text('// fixture header\n')
            products = root / 'Products'
            for name in ['CoreCompiler', 'MobileDevelopmentKit']:
                path = products / f'{name}.framework'
                path.mkdir(parents=True)
                (path / name).write_bytes(b'fixture binary')
            env = dict(os.environ, PATH=f'{bins}:{os.environ["PATH"]}',
                       COMPILER_LOG=str(log), NYXIAN_ROOT=str(frameworks),
                       IPHONEOS_SDK_PATH=str(root / 'SDK'), LITTER_BUILDKIT_NATIVE_MODE='inprocess',
                       LITTER_BUILDKIT_ENABLE_KITTYSTORE_SIGNER='0',
                       CORECOMPILER_FRAMEWORK=str(products / 'CoreCompiler.framework'),
                       MOBILEDEVELOPMENTKIT_FRAMEWORK=str(products / 'MobileDevelopmentKit.framework'))
            subprocess.run(['bash', str(script)], env=env, check=True, capture_output=True)
            commands = [json.loads(line) for line in log.read_text().splitlines()]
            compiled = [args[args.index('-c') + 1] for args in commands if '-c' in args]
            self.assertEqual({Path(p).name for p in compiled},
                             {'LitterBuildKitNative.mm', 'LitterBuildKitInProcess.mm'})
            linked = commands[-1]
            self.assertIn('MobileDevelopmentKit', linked)
            self.assertIn('CoreCompiler', linked)
            (products / 'MobileDevelopmentKit.framework/MobileDevelopmentKit').unlink()
            result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('framework executable is missing', result.stderr)
