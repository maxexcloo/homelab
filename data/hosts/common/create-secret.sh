#!/usr/bin/env bash
set -euo pipefail

printf '%s' "${CF_DNS_API_TOKEN}" | podman secret create --replace traefik-cloudflare - >/dev/null
