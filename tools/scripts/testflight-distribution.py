#!/usr/bin/env python3
"""Inspect or repair an existing TestFlight build using repository ASC credentials."""
import argparse
import base64
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

API = 'https://api.appstoreconnect.apple.com'


def token():
    def encode(value):
        return base64.urlsafe_b64encode(value).rstrip(b'=').decode()
    now = int(time.time())
    header = {'alg': 'ES256', 'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'}
    payload = {'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1199, 'aud': 'appstoreconnect-v1'}
    unsigned = '.'.join(encode(json.dumps(x).encode()) for x in (header, payload))
    der = subprocess.check_output(['openssl', 'dgst', '-sha256', '-sign', os.environ['ASC_PRIVATE_KEY_PATH']], input=unsigned.encode())
    # P-256 signatures have a short DER sequence containing two INTEGERs.
    if der[0] != 0x30 or der[1] >= 128:
        raise ValueError('Unexpected ES256 signature encoding')
    index, parts = 2, []
    for _ in range(2):
        if der[index] != 2:
            raise ValueError('Unexpected ES256 integer encoding')
        length = der[index + 1]
        part = der[index + 2:index + 2 + length].lstrip(b'\0')
        if len(part) > 32:
            raise ValueError('Invalid ES256 integer length')
        parts.append(part.rjust(32, b'\0'))
        index += 2 + length
    return unsigned + '.' + encode(b''.join(parts))


class Apple:
    def __init__(self):
        self.jwt = token()

    def request(self, path, method='GET', body=None):
        url = path if path.startswith(API + '/') else API + path
        if not url.startswith(API + '/'):
            raise ValueError('Unexpected pagination host')
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(url, data=data, method=method, headers={
            'Authorization': 'Bearer ' + self.jwt, 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            detail = json.loads(error.read())
            messages = [f"{e.get('code')}: {e.get('detail', e.get('title'))}" for e in detail.get('errors', [])]
            raise RuntimeError(f"Apple {error.code} {method} {path}: {'; '.join(messages)}") from None

    def collection(self, path):
        items = []
        while path:
            result = self.request(path)
            items.extend(result['data'])
            path = result.get('links', {}).get('next')
        return items


def inspect(apple, build_id, bundle_id, group_names, repair=False):
    build = apple.request(f'/v1/builds/{build_id}')['data']
    app = apple.request(f'/v1/builds/{build_id}/app')['data']
    if app['attributes']['bundleId'] != bundle_id:
        raise RuntimeError('Build belongs to a different bundle ID; refusing changes')
    attrs = build['attributes']
    print(f"App: {app['attributes']['name']} ({bundle_id})")
    print(f"Build: {attrs['version']}; processing={attrs['processingState']}; expired={attrs['expired']}")
    recent = apple.request(f"/v1/builds?filter[app]={app['id']}&sort=-uploadedDate&limit=5")['data']
    print('Latest Apple builds: ' + json.dumps([{k: b['attributes'].get(k) for k in ('version', 'uploadedDate', 'processingState', 'expired')} for b in recent[:5]]))
    beta = apple.request(f'/v1/builds/{build_id}/buildBetaDetail')['data']
    print('Apple testing states: ' + json.dumps(beta['attributes'], sort_keys=True))
    if attrs['expired'] or attrs['processingState'] != 'VALID':
        raise RuntimeError('Build is expired or not processed successfully; it cannot be distributed')
    groups = apple.collection(f"/v1/apps/{app['id']}/betaGroups?limit=200")
    problems = []
    external = False
    for name in group_names:
        matches = [g for g in groups if g['attributes']['name'] == name]
        if len(matches) != 1:
            problems.append(f'Expected exactly one beta group named {name}')
            continue
        group = matches[0]
        internal = group['attributes']['isInternalGroup']
        external |= not internal
        assigned = {b['id'] for b in apple.collection(f"/v1/betaGroups/{group['id']}/builds?limit=200")}
        testers = apple.collection(f"/v1/betaGroups/{group['id']}/betaTesters?limit=200")
        print(f"Group {name}: internal={internal}; testers={len(testers)}; assigned={build_id in assigned}")
        if not testers:
            problems.append(f'{name} has no testers; add the intended testers in App Store Connect')
        if build_id not in assigned:
            if repair:
                apple.request(f"/v1/betaGroups/{group['id']}/relationships/builds", 'POST', {'data': [{'type': 'builds', 'id': build_id}]})
                print(f'Assigned build to {name}')
            else:
                problems.append(f'Build is not assigned to {name}')
    state = beta['attributes'].get('externalBuildState')
    if external and repair and state == 'READY_FOR_BETA_SUBMISSION':
        apple.request('/v1/betaAppReviewSubmissions', 'POST', {'data': {'type': 'betaAppReviewSubmissions', 'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
        print('Submitted for Beta App Review')
    if repair and not beta['attributes'].get('autoNotifyEnabled'):
        apple.request(f"/v1/buildBetaDetails/{beta['id']}", 'PATCH', {'data': {'type': 'buildBetaDetails', 'id': beta['id'], 'attributes': {'autoNotifyEnabled': True}}})
        print('Enabled automatic tester notification')
    beta = apple.request(f'/v1/builds/{build_id}/buildBetaDetail')['data']['attributes']
    print('Final Apple testing states: ' + json.dumps(beta, sort_keys=True))
    if beta.get('internalBuildState') not in ('IN_BETA_TESTING', 'READY_FOR_BETA_TESTING'):
        problems.append('Internal testing blocked: ' + str(beta.get('internalBuildState')))
    if external:
        state = beta.get('externalBuildState')
        if state in ('WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW'):
            print('External testers are waiting for Apple beta review; no external update is available yet')
        elif state not in ('IN_BETA_TESTING', 'BETA_APPROVED', 'READY_FOR_BETA_TESTING'):
            problems.append('External testing blocked: ' + str(state))
    if problems:
        raise RuntimeError('; '.join(problems))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-id', required=True)
    parser.add_argument('--bundle-id', default='com.sigkitten.litter.39A8Q3T3TR')
    parser.add_argument('--groups', default='Internal Testers,Beta Testers')
    parser.add_argument('--repair', action='store_true')
    args = parser.parse_args()
    try:
        inspect(Apple(), args.build_id, args.bundle_id, [n.strip() for n in args.groups.split(',') if n.strip()], args.repair)
    except (RuntimeError, KeyError, ValueError) as error:
        print(f'::error::{error}')
        raise SystemExit(1)
