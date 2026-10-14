#!/usr/bin/env python3
"""Check Bento's native proxy routes against its owning host inventory."""
import ipaddress
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def read_yaml(path):
    return json.loads(subprocess.check_output(['yq', '-o=json', '.', str(path)]))


def main():
    inventory = read_yaml(ROOT / 'data/machines.yaml')['machines']['mbk']['bento']
    routes = read_yaml(ROOT / 'hosts/bento/etc/bento-proxy/routes.yaml')['http']
    quadlet = (ROOT / 'hosts/bento/etc/containers/systemd/bento-proxy.container').read_text()
    expected = {name: service for name, service in inventory['services'].items() if 'backend_port' in service}
    assert set(routes['routers']) == set(expected), 'Proxy routes differ from the named host services'
    assert set(routes['services']) == set(expected), 'Proxy backends differ from the named host services'
    for name, service in expected.items():
        route = routes['routers'][name]
        assert route['rule'] == f"Host(`{service['hostname']}`)", f'{name}: hostname differs from inventory'
        assert route['service'] == name, f'{name}: incorrect backend'
        entries = {'tailnet', 'tailnet-v6'} | ({'lan'} if service.get('lan') else set())
        assert set(route['entryPoints']) == entries, f'{name}: incorrect network boundary'
        assert route['tls'] == {'certResolver': 'letsencrypt'}, f'{name}: HTTPS resolver required'
        servers = routes['services'][name]['loadBalancer']['servers']
        assert servers == [{'url': f"http://127.0.0.1:{service['backend_port']}"}], f'{name}: backend must use loopback'
        assert service['scheme'] == 'https' and service['port'] == 443
    # Host-bound listeners prevent a LAN request with a private Host header from matching.
    assert f"--entryPoints.lan.address={inventory['interfaces'][0]['address']}:443" in quadlet
    assert '--entryPoints.tailnet.address=${BENTO_TAILSCALE_IPV4}:443' in quadlet
    assert '--entryPoints.tailnet-v6.address=[${BENTO_TAILSCALE_IPV6}]:443' in quadlet
    assert '--configFile' not in quadlet, 'Keep all static configuration in one supported source'
    assert '--providers.file.filename=/etc/bento-proxy/routes.yaml' in quadlet
    assert '--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json' in quadlet
    assert '--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare' in quadlet
    addresses = (ROOT / 'hosts/bento/etc/systemd/system/bento-proxy-addresses.service').read_text()
    assert 'BENTO_TAILSCALE_IPV4=%%s' in addresses and 'BENTO_TAILSCALE_IPV6=%%s' in addresses, 'Escape systemd specifiers in shell formats'
    assert 'Network=host' in quadlet and 'EnvironmentFile=/run/bento-proxy/addresses.env' in quadlet
    assert 'Environment=CF_DNS_API_TOKEN_FILE=/run/secrets/cloudflare' in quadlet
    unit = (ROOT / 'hosts/bento/etc/systemd/system/ai-https.service').read_text()
    network = read_yaml(ROOT / 'data/networks.yaml')['networks']['mbk']['subnets']['default']['cidr']
    rule = re.search(r'source address="([^"]+)" destination address="([^"]+)" port port="443"', unit)
    allowed = rule.group(1)
    assert rule.group(2) == inventory['interfaces'][0]['address'], 'LAN firewall must exclude Tailscale destinations'
    assert ipaddress.ip_network(allowed, strict=False) == ipaddress.ip_network(network, strict=False)
    assert '--https=443 ' not in unit, 'Tailscale Serve must release the proxy HTTPS port'
    assert '--https=8445 ' in unit, 'Keep private Files access'
    print('Bento proxy names, backends, HTTPS and LAN/Tailscale boundaries passed.')


if __name__ == '__main__':
    main()
