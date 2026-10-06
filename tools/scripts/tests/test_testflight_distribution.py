import importlib.util
import unittest
import urllib.parse
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
    def test_build_number_resolution_is_scoped_to_requested_app(self):
        class Lookup:
            def collection(self, path):
                query = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query)
                if path.startswith('/v1/apps?'):
                    self.bundle = query['filter[bundleId]'][0]
                    return [{'id': 'expected-app'}]
                self.filters = query
                return [{'id': 'apple-build-id'}]
        apple = Lookup()
        self.assertEqual(m.resolve_build(apple, '20261006181035', 'expected'), 'apple-build-id')
        self.assertEqual(apple.bundle, 'expected')
        self.assertEqual(apple.filters, {'filter[app]': ['expected-app'], 'filter[version]': ['20261006181035']})

    def test_missing_or_ambiguous_build_number_is_rejected(self):
        class Lookup:
            def collection(self, path):
                return [{'id': 'app'}] if path.startswith('/v1/apps?') else self.builds
        for builds in ([], [{'id': 'one'}, {'id': 'two'}]):
            apple = Lookup()
            apple.builds = builds
            with self.assertRaisesRegex(RuntimeError, 'exactly one uploaded build'):
                m.resolve_build(apple, '123', 'expected')

    def test_existing_record_id_needs_no_lookup(self):
        self.assertEqual(m.resolve_build(None, 'apple-build-id', 'expected'), 'apple-build-id')

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

    def test_empty_group_names_rejected_without_mutations(self):
        for names in ([], [' ', '']):
            apple = AppleFake()
            with self.assertRaisesRegex(ValueError, 'At least one beta group'):
                m.inspect(apple, 'build', 'expected', names, True)
            self.assertFalse(apple.mutations)

    def test_external_only_does_not_require_internal_testing(self):
        apple = AppleFake(internal='MISSING_EXPORT_COMPLIANCE')
        m.inspect(apple, 'build', 'expected', ['Beta Testers'], False)
        self.assertFalse(apple.mutations)

    def test_internal_only_does_not_require_external_testing(self):
        m.inspect(AppleFake(external='MISSING_EXPORT_COMPLIANCE'),
                  'build', 'expected', ['Internal Testers'], False)

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
