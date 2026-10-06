import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / 'build-matched-nyxian-toolchain.sh'


class GeneratedHeaderPackagingTests(unittest.TestCase):
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
