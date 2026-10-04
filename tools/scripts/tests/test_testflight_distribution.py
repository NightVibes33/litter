import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('distribution', Path(__file__).parents[1] / 'testflight-distribution.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class AppleFake:
    def __init__(self, *, expired=False, internal='IN_BETA_TESTING', external='IN_BETA_TESTING', testers=True, bundle='expected', assigned=True):
        self.expired, self.testers, self.bundle, self.assigned = expired, testers, bundle, assigned
        self.states = {'internalBuildState': internal, 'externalBuildState': external, 'autoNotifyEnabled': False}
        self.mutations = []

    def request(self, path, method='GET', body=None):
        if method != 'GET':
            self.mutations.append((path, method, body))
            if path == '/v1/betaAppReviewSubmissions':
                self.states['externalBuildState'] = 'WAITING_FOR_BETA_REVIEW'
            if path.startswith('/v1/buildBetaDetails/'):
                self.states['autoNotifyEnabled'] = True
            return {}
        if path.startswith('/v1/builds?'):
            return {'data': []}
        if path.endswith('/app'):
            return {'data': {'id': 'app', 'attributes': {'name': 'Alley Cat', 'bundleId': self.bundle}}}
        if path.endswith('/buildBetaDetail'):
            return {'data': {'id': 'beta', 'attributes': self.states.copy()}}
        return {'data': {'attributes': {'version': '123', 'processingState': 'VALID', 'expired': self.expired}}}

    def collection(self, path):
        if '/betaTesters?' in path:
            return [{'id': 'tester'}] if self.testers else []
        if '/builds?' in path or path.startswith('/v1/builds?'):
            return [{'id': 'build', 'attributes': {}}] if self.assigned else []
        groups = [{'id': 'internal', 'attributes': {'name': 'Internal Testers', 'isInternalGroup': True}}, {'id': 'external', 'attributes': {'name': 'Beta Testers', 'isInternalGroup': False}}]
        return [] if path.startswith('/v1/builds/') and not self.assigned else groups


class DistributionTests(unittest.TestCase):
    def inspect(self, apple, repair=True):
        return m.inspect(apple, 'build', 'expected', ['Internal Testers', 'Beta Testers'], repair)

    def test_expired_build_rejected_without_mutations(self):
        apple = AppleFake(expired=True)
        with self.assertRaisesRegex(RuntimeError, 'expired'):
            self.inspect(apple)
        self.assertFalse(apple.mutations)

    def test_wrong_app_rejected_without_mutations(self):
        apple = AppleFake(bundle='upstream')
        with self.assertRaisesRegex(RuntimeError, 'different bundle'):
            self.inspect(apple)
        self.assertFalse(apple.mutations)

    def test_empty_groups_fail(self):
        with self.assertRaisesRegex(RuntimeError, 'no testers'):
            self.inspect(AppleFake(testers=False))

    def test_compliance_block_not_reported_as_success(self):
        with self.assertRaisesRegex(RuntimeError, 'MISSING_EXPORT_COMPLIANCE'):
            self.inspect(AppleFake(internal='MISSING_EXPORT_COMPLIANCE'))

    def test_repair_assigns_build_submits_review_and_enables_notifications(self):
        apple = AppleFake(external='READY_FOR_BETA_SUBMISSION', assigned=False)
        self.inspect(apple)
        self.assertEqual([method for _, method, _ in apple.mutations], ['POST', 'POST', 'POST', 'PATCH'])
        self.assertEqual(apple.states['externalBuildState'], 'WAITING_FOR_BETA_REVIEW')

    def test_read_only_inspection_never_mutates(self):
        apple = AppleFake()
        self.inspect(apple, False)
        self.assertFalse(apple.mutations)


if __name__ == '__main__':
    unittest.main()
