import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / 'build-matched-nyxian-toolchain.sh'


class GeneratedHeaderPackagingTests(unittest.TestCase):
    def test_built_framework_replaces_legacy_support_framework(self):
        script = SCRIPT.read_text()
        start = script.index('cp -R "$LLVM_SOURCE/CoreCompilerSupportLibs/."')
        end = script.index('\nHEADERS=', start)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            llvm = root / 'llvm'
            staging = root / 'staging'
            (staging / 'CoreCompilerSupportLibs').mkdir(parents=True)
            legacy = llvm / 'CoreCompilerSupportLibs/LLVM.xcframework/ios-arm64/Headers/swift/bridging'
            legacy.mkdir(parents=True)
            (legacy / 'obsolete.h').write_text('stale framework')
            source = llvm / 'source-bridging'
            source.mkdir()
            (source / 'bridging.h').write_text('matching header')
            built = llvm / 'LLVM.xcframework/ios-arm64/Headers/swift'
            built.mkdir(parents=True)
            (built / 'bridging').symlink_to(source, target_is_directory=True)
            subprocess.run(
                ['bash', '-e', '-c', script[start:end]],
                env={**os.environ, 'LLVM_SOURCE': str(llvm), 'STAGING': str(staging)},
                check=True, capture_output=True,
            )
            headers = staging / 'CoreCompilerSupportLibs/LLVM.xcframework/ios-arm64/Headers/swift/bridging'
            self.assertFalse(headers.is_symlink())
            self.assertEqual((headers / 'bridging.h').read_text(), 'matching header')
            self.assertFalse((headers / 'obsolete.h').exists())

    def test_generated_bridging_link_merges_with_source_directory(self):
        script = SCRIPT.read_text()
        start = script.index('for generated in ')
        end = script.index('\ndone', start) + len('\ndone')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = root / 'build'
            headers = root / 'Headers'
            source = root / 'source-bridging'
            source.mkdir()
            (source / 'bridging.h').write_text('source bridging header\n')
            (headers / 'swift/bridging').mkdir(parents=True)
            (headers / 'swift/bridging/retained.h').write_text('retain source-only header\n')
            (headers / 'swift/Config.h').write_text('old config\n')
            generated = build / 'swift-iphoneos-arm64/include/swift'
            generated.mkdir(parents=True)
            (generated / 'bridging').symlink_to(source, target_is_directory=True)
            (generated / 'Config.h').write_text('matching generated config\n')
            subprocess.run(
                ['bash', '-e', '-c', script[start:end]],
                env={**os.environ, 'BUILD_ROOT': str(build), 'HEADERS': str(headers)},
                check=True, capture_output=True,
            )
            self.assertFalse((headers / 'swift/bridging').is_symlink())
            self.assertEqual((headers / 'swift/bridging/bridging.h').read_text(), 'source bridging header\n')
            self.assertTrue((headers / 'swift/bridging/retained.h').is_file())
            self.assertEqual((headers / 'swift/Config.h').read_text(), 'matching generated config\n')
