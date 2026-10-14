#!/usr/bin/env python3
"""Preview or apply only Bento Normal's Control D home DNS override."""
import argparse
import ipaddress
import json
from pathlib import Path
import re
import subprocess
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]


def normal_rule():
    inventory = json.loads(subprocess.check_output(['yq', '-o=json', '.', str(ROOT / 'data/machines.yaml')]))
    bento = inventory['machines']['mbk']['bento']
    normal = bento['services']['heiss']
    if not normal.get('lan') or any(service.get('lan') for name, service in bento['services'].items() if name != 'heiss'):
        raise ValueError('Only the Normal studio may have a home DNS override.')
    address = bento['interfaces'][0]['address']
    ipaddress.IPv4Address(address)
    # Disable the public Tailscale AAAA answer on Wi-Fi alongside the IPv4 override.
    return {'do': 2, 'hostnames': [normal['hostname']], 'status': 1, 'via': address, 'via_v6': '::'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', help='Control D profile used by home Wi-Fi clients')
    parser.add_argument('--apply', action='store_true', help='Apply and verify the displayed single-host override')
    parser.add_argument('--credential', help='1Password reference for the Control D API token')
    arguments = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', arguments.profile):
        parser.error('Invalid Control D profile ID.')
    rule = normal_rule()
    print(json.dumps({'profile': arguments.profile, 'rule': rule}, indent=2))
    if not arguments.apply:
        return
    if not arguments.credential or not arguments.credential.startswith('op://'):
        parser.error('--apply requires a 1Password --credential reference.')
    # Resolve the token only inside this credential-consuming process.
    result = subprocess.run(['op', 'read', arguments.credential], capture_output=True, text=True)
    if result.returncode or not result.stdout.strip():
        raise SystemExit('Could not resolve the configured Control D credential.')
    token = result.stdout.strip()
    url = f'https://api.controld.com/profiles/{arguments.profile}/rules'

    def request(method, payload=None):
        body = json.dumps(payload).encode() if payload is not None else None
        query = Request(url, data=body, headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}, method=method)
        try:
            with urlopen(query, timeout=30) as response:
                data = json.load(response)
        except (HTTPError, URLError):
            raise SystemExit('Control D request failed; no credential or response body was logged.') from None
        if data.get('success') is not True:
            raise SystemExit('Control D rejected the request; inspect the profile in its dashboard.')
        return data

    hostname = rule['hostnames'][0]
    existing = [item for item in request('GET')['body']['rules'] if item['PK'] == hostname]
    if len(existing) > 1:
        raise SystemExit('Multiple rules exist for the Normal hostname; reconcile them before applying.')
    wanted = {key: value for key, value in rule.items() if key != 'hostnames'}
    if not existing or any(existing[0]['action'].get(key) != value for key, value in wanted.items()):
        request('PUT' if existing else 'POST', rule)
    verified = [item for item in request('GET')['body']['rules'] if item['PK'] == hostname]
    if len(verified) != 1 or any(verified[0]['action'].get(key) != value for key, value in wanted.items()):
        raise SystemExit('Control D verification failed; inspect the Normal hostname rule.')
    print('Normal home DNS override verified; private studio and control DNS were untouched.')


if __name__ == '__main__':
    main()
