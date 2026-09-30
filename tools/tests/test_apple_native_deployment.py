"""Regression coverage for pre-LC_BUILD_VERSION simulator archives."""
import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location(
    'deployment', Path(__file__).parents[1] / 'scripts/verify-unicorn-deployment.py')
deployment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deployment)


def object_file(cpu, command):
    header = struct.pack('<IIIIIIII', 0xfeedfacf, cpu, 0, 1, 1, len(command), 0, 0)
    return header + command


class DeploymentMetadataTests(unittest.TestCase):
    def test_legacy_x86_ios_objects_are_simulator_objects(self):
        command = struct.pack('<IIII', 0x25, 16, 10 << 16, 0)
        self.assertEqual(list(deployment.versions(object_file(0x01000007, command))), [(7, 10 << 16)])

    def test_legacy_arm_ios_objects_remain_device_objects(self):
        command = struct.pack('<IIII', 0x25, 16, 10 << 16, 0)
        self.assertEqual(list(deployment.versions(object_file(0x0100000c, command))), [(2, 10 << 16)])

    def test_modern_explicit_platform_is_preserved(self):
        command = struct.pack('<IIIIII', 0x32, 24, 2, 18 << 16, 0, 0)
        self.assertEqual(list(deployment.versions(object_file(0x01000007, command))), [(2, 18 << 16)])


if __name__ == '__main__':
    unittest.main()
